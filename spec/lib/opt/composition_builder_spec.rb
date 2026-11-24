require "rails_helper"

RSpec.describe Opt::CompositionBuilder do
  describe "日本語前提の既定値" do
    # 実物fixture: Archetype Designerからlang=jaでエクスポートしたOPT
    # (openEHR-EHR-COMPOSITION.encounter.v1 + openEHR-EHR-OBSERVATION.blood_pressure.v2)。
    # 登録OPTはlang=ja前提とする方針 (docs/design/pathcards-language-policy.md)
    # に合わせ、保存されるCompositionの既定言語・地域もja/JPであることを仕様として固定する。
    let(:source_xml) { Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read }

    # 保存→reloadでweb_templateをJSON往復させ、本番経路(登録済みテンプレート)と
    # 同じ文字列キー状態にする
    let(:template) { Template.build_from_opt_xml(source_xml).tap(&:save!).reload }

    # CompositionBuilderは全フィールドの値を要求する(@values.fetch)ため、
    # rm_typeごとの妥当なサンプル値を全フィールドに供給する
    let(:values) do
      samples = {
        "DV_QUANTITY" => "120",
        "DV_COUNT" => "1",
        "DV_BOOLEAN" => "true",
        "DV_DATE" => "2026-08-21",
        "DV_DATE_TIME" => "2026-08-21T10:00:00+09:00"
      }
      template.fields.to_h { |field| [ field["name"], samples.fetch(field["rm_type"], "テキスト") ] }
    end

    let(:composition) { described_class.new(template, values).build }

    it "Compositionのlanguageはja (ISO_639-1) になる" do
      expect(composition.language.code_string).to eq("ja")
    end

    it "CompositionのterritoryはJP (ISO_3166-1) になる" do
      expect(composition.territory.code_string).to eq("JP")
    end

    # skoba/anlage#54: ルートは COMPOSITION アーキタイプの ID（OPT の definition ルート）を
    # archetype_node_id に持ち、archetype_details を持つ。template_id は archetype_details に入る。
    describe "ルート（COMPOSITION）" do
      it "archetype_node_id は COMPOSITION アーキタイプの ID になる（template_id ではない）" do
        expect(composition.archetype_node_id).to eq("openEHR-EHR-COMPOSITION.encounter.v1")
      end

      it "archetype_details に archetype_id、template_id、RM version を持つ" do
        expect(composition.archetype_details.archetype_id.value).to eq("openEHR-EHR-COMPOSITION.encounter.v1")
        expect(composition.archetype_details.template_id.value).to eq(template.template_id)
        expect(composition.archetype_details.rm_version).to eq(described_class::RM_VERSION)
      end

      it "root_archetype_id を持たない登録済みの web_template（#54 より前の登録）でも、OPT から引いて組む" do
        template.update!(web_template: template.web_template.except("root_archetype_id"))

        expect(described_class.new(template.reload, values).build.archetype_node_id).to eq("openEHR-EHR-COMPOSITION.encounter.v1")
      end
    end

    describe "ENTRYのarchetype_details" do
      let(:entry) { template.entries.first }
      let(:built_entry) { composition.content.first }

      it "archetype_id、template_id、RM versionを設定する" do
        expect(built_entry.archetype_details.archetype_id.value).to eq(entry["archetype_id"])
        expect(built_entry.archetype_details.template_id.value).to eq(template.web_template["template_id"])
        expect(built_entry.archetype_details.rm_version).to eq(described_class::RM_VERSION)
      end
    end
  end
end

# skoba/anlage#33: builder は input_kind を読むだけ。coded_free は DV_TEXT（OR 制約の
# 正規の一方）、coded_manual は手入力の system/code で DvCodedText。
RSpec.describe Opt::CompositionBuilder, "#33 input_kind" do
  let(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!).reload }
  let(:base_values) do
    { "problem_diagnosis_at0077" => "2026-03-01T00:00:00", "problem_diagnosis_at0003" => "2026-03-01T00:00:00",
      "problem_diagnosis_at0030" => "2026-03-01T00:00:00", "problem_diagnosis_at0073" => "at0074" }
  end

  def diagnosis_value(values)
    described_class.new(template, values).build.content.first.data.items.find { |item| item.archetype_node_id == "at0002" }.value
  end

  it "coded_free（ProblemList 傷病名）は DvText で保存する" do
    value = diagnosis_value(base_values.merge("problem_diagnosis_at0002" => "2型糖尿病"))

    expect(value).to be_a(OpenEHR::RM::DataTypes::Text::DvText)
    expect(value).not_to be_a(OpenEHR::RM::DataTypes::Text::DvCodedText)
    expect(value.value).to eq("2型糖尿病")
  end

  it "coded_manual は手入力の system/code で DvCodedText を組む" do
    field = template.fields.find { |f| f["name"] == "problem_diagnosis_at0002" }
    field["input_kind"] = "coded_manual"
    template.update_column(:web_template, template.web_template)
    template.reload

    value = diagnosis_value(base_values.merge("problem_diagnosis_at0002" => "2型糖尿病", "problem_diagnosis_at0002__code" => "5A11", "problem_diagnosis_at0002__system" => "http://id.who.int/icd/release/11/mms"))

    expect(value).to be_a(OpenEHR::RM::DataTypes::Text::DvCodedText)
    expect(value.defining_code.code_string).to eq("5A11")
    expect(value.defining_code.terminology_id.value).to eq("http://id.who.int/icd/release/11/mms")
  end
end

# skoba/anlage#34: 空欄（nil／""）の要素は Composition に含めない（要素単位・型別ガードに
# しない）。builder が送信値へ直接 Float／Integer／Date.parse／Time.zone.parse／iso8601 を
# 呼ぶ 5 箇所は、非 blank の要素でしか到達しない。
RSpec.describe Opt::CompositionBuilder, "#34 空欄の要素はスキップ" do
  let(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!).reload }

  it "DV_DATE_TIME・DV_CODED_TEXT の空欄を含む値でも組め、埋めた要素だけになる" do
    composition = described_class.new(template, {
      "problem_diagnosis_at0002" => "かぜ", "problem_diagnosis_at0077" => "2026-09-25T00:00:00",
      "problem_diagnosis_at0003" => "", "problem_diagnosis_at0030" => nil, "problem_diagnosis_at0073" => ""
    }).build

    expect(composition.content.first.data.items.map(&:archetype_node_id)).to eq(%w[at0002 at0077])
  end

  it "全要素が空欄の entry は content に含めない" do
    composition = described_class.new(template, { "problem_diagnosis_at0002" => "", "problem_diagnosis_at0077" => "" }).build

    expect(composition.content).to be_empty
  end
end

# skoba/anlage#35: 日時は Time 経由をやめ、入力を ISO 部分精度の文字列のまま保存する。
# 存在しない精度（午前 0 時・秒・タイムゾーン）を付けない。
RSpec.describe Opt::CompositionBuilder, "#35 日付・時刻の部分精度保存" do
  let(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!).reload }

  def onset_value(values)
    described_class.new(template, { "problem_diagnosis_at0002" => "かぜ" }.merge(values)).build
      .content.first.data.items.find { |item| item.archetype_node_id == "at0077" }.value
  end

  it "日付のみなら 2026-09-22 のまま（DvDateTime、午前 0 時を付けない）" do
    value = onset_value("problem_diagnosis_at0077" => "2026-09-22")

    expect(value).to be_a(OpenEHR::RM::DataTypes::Quantity::DateTime::DvDateTime)
    expect(value.value).to eq("2026-09-22")
    expect(JSON.parse(OpenEHR::Serializer::RMJSONSerializer.new(value).serialize)["value"]).to eq("2026-09-22")
  end

  it "日付＋時刻なら 2026-09-22T14:30（秒・タイムゾーンを付けない）" do
    value = onset_value("problem_diagnosis_at0077" => "2026-09-22", "problem_diagnosis_at0077__time" => "14:30")

    expect(value.value).to eq("2026-09-22T14:30")
  end

  it "DV_DATE は DvDate、DV_TIME は DvTime を文字列のまま組む" do
    field = template.fields.find { |f| f["name"] == "problem_diagnosis_at0077" }
    field["rm_type"] = "DV_DATE"; field["input_kind"] = "date"
    template.update_column(:web_template, template.web_template); template.reload
    expect(onset_value("problem_diagnosis_at0077" => "2026-09")).to be_a(OpenEHR::RM::DataTypes::Quantity::DateTime::DvDate)

    field = template.fields.find { |f| f["name"] == "problem_diagnosis_at0077" }
    field["rm_type"] = "DV_TIME"; field["input_kind"] = "time"
    template.update_column(:web_template, template.web_template); template.reload
    time = onset_value("problem_diagnosis_at0077" => "14:30")
    expect(time).to be_a(OpenEHR::RM::DataTypes::Quantity::DateTime::DvTime)
    expect(time.value).to eq("14:30")
  end
end

# skoba/anlage#38: 埋め込み CLUSTER 一段を ITEM_TREE → CLUSTER（archetype_details 付き）→ ELEMENT で組む。
# skoba/anlage#37: number は magnitude＋units（__units、リストがあれば既定＝先頭）で DvQuantity。
RSpec.describe Opt::CompositionBuilder, "#38 埋め込み CLUSTER 一段・#37 units" do
  let(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/LabResultReport.opt").read).tap(&:save!).reload }

  it "検査名は ITEM_TREE 直下、分析名と数値は CLUSTER.laboratory_test_analyte 配下に入る" do
    composition = described_class.new(template, {
      "laboratory_test_result_at0005" => "血糖", "laboratory_test_analyte_at0024" => "空腹時血糖",
      "laboratory_test_analyte_at0001" => "98", "laboratory_test_analyte_at0001__units" => "mg/dL"
    }).build

    tree = composition.content.first.data.events.first.data
    expect(tree.items.map(&:archetype_node_id)).to eq([ "at0005", "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1" ])
    cluster = tree.items.last
    expect(cluster).to be_a(OpenEHR::RM::DataStructures::ItemStructure::Representation::Cluster)
    expect(cluster.archetype_details.archetype_id.value).to eq("openEHR-EHR-CLUSTER.laboratory_test_analyte.v1")
    expect(cluster.name.value).to eq("検査分析結果")
    expect(cluster.items.map(&:archetype_node_id)).to eq(%w[at0024 at0001])
    quantity = cluster.items.last.value
    expect(quantity.magnitude).to eq(98.0)
    expect(quantity.units).to eq("mg/dL")
  end
end

# skoba/anlage#80（M2 の B）: SECTION 配下の ENTRY を、SECTION の items に入れて組む。
# 実物 fixture: jp_referral.opt v0.2（SECTION referral_details の配下に 5 つの ENTRY）。
# 値を入れるのは傷病名（EVALUATION）と現病歴（OBSERVATION）だけ。空欄の ENTRY は組まれない（#34）ので、
# INSTRUCTION と、field 名が衝突する clinical_synopsis ×2 はこの spec に関わらない。
RSpec.describe Opt::CompositionBuilder, "#80 SECTION 配下の ENTRY" do
  let(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/jp_referral.opt").read).tap(&:save!).reload }
  let(:values) { { "problem_diagnosis_at0002" => "高血圧症", "story" => "3 か月前から頭痛" } }
  let(:composition) { described_class.new(template, values).build }
  let(:section) { composition.content.first }

  it "content には SECTION が 1 つ入り、archetype_node_id・テンプレート上の名前・archetype_details を持つ" do
    expect(composition.content.map(&:class)).to eq([ OpenEHR::RM::Composition::Content::Navigation::Section ])
    expect(section.archetype_node_id).to eq("openEHR-EHR-SECTION.referral_details.v0")
    expect(section.name.value).to eq("紹介状の詳細情報")
    expect(section.archetype_details.archetype_id.value).to eq("openEHR-EHR-SECTION.referral_details.v0")
    expect(section.archetype_details.template_id.value).to eq("jp_referral")
  end

  it "SECTION 配下の EVALUATION と OBSERVATION を、SECTION の items に入れて組む" do
    expect(section.items.map(&:archetype_node_id))
      .to eq(%w[openEHR-EHR-EVALUATION.problem_diagnosis.v1 openEHR-EHR-OBSERVATION.story.v1])

    evaluation, observation = section.items
    expect(evaluation.data.archetype_node_id).to eq("at0001")
    expect(evaluation.data.items.map { |item| [ item.archetype_node_id, item.value.value ] }).to eq([ [ "at0002", "高血圧症" ] ])
    expect(observation.data.archetype_node_id).to eq("at0001")
    expect(observation.data.events.first.archetype_node_id).to eq("at0002")
    expect(observation.data.events.first.data.items.map { |item| [ item.archetype_node_id, item.value.value ] })
      .to eq([ [ "at0004", "3 か月前から頭痛" ] ])
  end

  it "組んだ Composition を RM グラフにコミットでき、SECTION 越しの path で引ける" do
    Opt::RmCompositionCommitter.call(template, values)

    result = OpenehrRails::Aql::Executor.execute(<<~AQL)
      SELECT e/data[at0001]/items[at0002]/value/value
      FROM EHR e2 CONTAINS COMPOSITION c CONTAINS EVALUATION e[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
    AQL
    expect(result.rows).to eq([ [ "高血圧症" ] ])
  end

  it "content 直下の ENTRY は従来どおり content に直接入る（ProblemList）" do
    problem_list = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!).reload
    built = described_class.new(problem_list, { "problem_diagnosis_at0002" => "高血圧症" }).build

    expect(built.content.map(&:class)).to eq([ OpenEHR::RM::Composition::Content::Entry::Evaluation ])
  end
end

# skoba/anlage#86: 保存される CODE_PHRASE の terminology_id が値を持つ
# （docs/design/rm-attributes-without-inputs.md 4 節の 1）。canonical JSON で確かめる。
RSpec.describe Opt::CompositionBuilder, "#86 terminology_id の値" do
  let(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!).reload }
  let(:canonical) do
    built = described_class.new(template, { "problem_diagnosis_at0002" => "高血圧症", "problem_diagnosis_at0073" => "at0074" }).build
    JSON.parse(OpenEHR::Serializer::RMJSONSerializer.new(built).serialize)
  end
  let(:entry) { canonical["content"].first }

  it "COMPOSITION の言語・地域・category の terminology_id が値を持つ" do
    expect(canonical.dig("language", "terminology_id", "value")).to eq("ISO_639-1")
    expect(canonical.dig("territory", "terminology_id", "value")).to eq("ISO_3166-1")
    expect(canonical.dig("category", "defining_code", "terminology_id", "value")).to eq("openehr")
  end

  it "ENTRY の言語・文字コードの terminology_id が値を持つ" do
    expect(entry.dig("language", "terminology_id", "value")).to eq("ISO_639-1")
    expect(entry.dig("encoding", "terminology_id", "value")).to eq("IANA_character-sets")
  end

  it "選択肢（DV_CODED_TEXT）の terminology_id が値を持つ" do
    certainty = entry.dig("data", "items").find { |item| item["archetype_node_id"] == "at0073" }

    expect(certainty.dig("value", "defining_code")).to include("code_string" => "at0074", "terminology_id" => { "_type" => "TERMINOLOGY_ID", "value" => "local" })
  end
end

# skoba/anlage#87: COMPOSITION の category は value が表示（event）、code_string がコード（433）。
# OPT が category を 1 つのコードに絞っていれば、そのコードを使う
# （docs/design/rm-attributes-without-inputs.md 2 節の規則 1、4 節の 2）。
RSpec.describe Opt::CompositionBuilder, "#87 COMPOSITION の category" do
  let(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!).reload }
  let(:values) { { "problem_diagnosis_at0002" => "高血圧症" } }

  def category_of(template)
    canonical = JSON.parse(OpenEHR::Serializer::RMJSONSerializer.new(described_class.new(template, values).build).serialize)
    canonical["category"].then { |c| [ c["value"], c.dig("defining_code", "code_string"), c.dig("defining_code", "terminology_id", "value") ] }
  end

  it "value は event、code_string は 433、用語体系は openehr" do
    expect(category_of(template)).to eq(%w[event 433 openehr])
  end

  it "登録時に、OPT が絞っている category のコードを web_template に持つ（ProblemList.opt は 433）" do
    expect(template.web_template["category_code"]).to eq("433")
  end

  it "OPT が category を絞っていれば、設定の既定値ではなく OPT のコードを使う" do
    allow(OpenehrRails).to receive(:default_category).and_return(%w[431 persistent])

    expect(category_of(template)).to eq(%w[event 433 openehr])
  end

  it "category_code を持たない登録済みの web_template（#87 より前の登録）では、設定の既定値を正しい向きで使う" do
    template.update!(web_template: template.web_template.except("category_code"))
    allow(OpenehrRails).to receive(:default_category).and_return(%w[431 persistent])

    expect(category_of(template.reload)).to eq(%w[persistent 431 openehr])
  end
end
