require "rails_helper"

RSpec.describe Opt::PathcardExtractor do
  describe ".call" do
    it "returns schema-v1 shaped pathcards for the CardiologyEncounter OPT" do
      source_xml = Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)

      expect(result.cards).to be_an(Array)
      expect(result.cards).not_to be_empty
      expect(result.cards).to all(
        include(
          "schema_version" => "1.2",
          "identity" => be_a(Hash),
          "semantics" => include(
            "labels" => be_an(Array),
            "descriptions" => be_an(Array),
            "rm_type" => be_a(String)
          ),
          "constraints" => be_a(Hash),
          "bindings" => be_an(Array),
          "capture" => be_a(Hash),
          "reserved" => be_a(Hash),
          "provenance" => be_a(Hash)
        )
      )

      result.cards.each do |card|
        alternatives = card.dig("semantics", "rm_type_alternatives")
        expect(alternatives).to include(card.dig("semantics", "rm_type")) if alternatives
      end
    end

    it "extracts the blood pressure systolic identity from CardiologyEncounter" do
      source_xml = Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)

      expect(result.cards).to include(
        include(
          "identity" => {
            "template_id" => "CardiologyEncounter",
            "archetype_id" => "openEHR-EHR-OBSERVATION.blood_pressure.v2",
            "path" => "/content[openEHR-EHR-OBSERVATION.blood_pressure.v2]/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value",
            "at_code" => "at0004"
          },
          "constraints" => {
            "occurrences" => { "lower" => 0, "upper" => 1 },
            "value" => {
              "property" => { "terminology" => "openehr", "code" => "125" },
              "units" => "mm[Hg]",
              "magnitude_range" => {
                "lower" => 0.0,
                "upper" => 1000.0,
                "lower_included" => true,
                "upper_included" => false
              },
              "precision_range" => { "lower" => 0, "upper" => 0 }
            }
          }
        )
      )
    end

    it "tracks the embedded laboratory analyte archetype identity in LabResultReport" do
      source_xml = Rails.root.join("spec/fixtures/opt/LabResultReport.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)

      expect(result.cards).to include(
        include(
          "identity" => {
            "template_id" => "LabResultReport",
            "archetype_id" => "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1",
            "path" => "/content[openEHR-EHR-OBSERVATION.laboratory_test_result.v1]/data[at0001]/events[at0002]/data[at0003]/items[openEHR-EHR-CLUSTER.laboratory_test_analyte.v1]/items[at0001]/value",
            "at_code" => "at0001"
          }
        )
      )
    end

    it "extracts the Japanese systolic label from CardiologyEncounter" do
      source_xml = Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)
      card = result.cards.find do |candidate|
        candidate.dig("identity", "archetype_id") == "openEHR-EHR-OBSERVATION.blood_pressure.v2" &&
          candidate.dig("identity", "at_code") == "at0004"
      end

      expect(card.dig("semantics", "labels")).to eq([
        {
          "lang" => "ja",
          "text" => "収縮期",
          "untranslated_suspect" => false,
          "untranslated_evidence" => nil,
          "source_lang" => nil
        }
      ])
    end

    it "extracts the fallback-marked analyte description from LabResultReport" do
      source_xml = Rails.root.join("spec/fixtures/opt/LabResultReport.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)
      card = result.cards.find do |candidate|
        candidate.dig("identity", "archetype_id") == "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1" &&
          candidate.dig("identity", "at_code") == "at0001"
      end

      expect(card.dig("semantics", "descriptions")).to eq([
        {
          "lang" => "ja",
          "text" => "*The value of the analyte result. (en)",
          "untranslated_suspect" => true,
          "untranslated_evidence" => "fallback_marker",
          "source_lang" => "en"
        }
      ])
    end

    it "reports the fallback-marked analyte description from LabResultReport" do
      source_xml = Rails.root.join("spec/fixtures/opt/LabResultReport.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)

      expect(result.report.fetch(:untranslated_suspects)).to include(
        {
          "archetype_id" => "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1",
          "at_code" => "at0001",
          "field" => "description",
          "text" => "*The value of the analyte result. (en)",
          "evidence" => "fallback_marker"
        }
      )
    end

    it "extracts the local code list for diagnostic certainty from ProblemList" do
      source_xml = Rails.root.join("spec/fixtures/opt/ProblemList.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)
      card = result.cards.find do |candidate|
        candidate.dig("identity", "archetype_id") == "openEHR-EHR-EVALUATION.problem_diagnosis.v1" &&
          candidate.dig("identity", "at_code") == "at0073"
      end

      expect(card.dig("constraints", "value")).to eq(
        "code_list" => [
          { "code" => "at0074", "label" => "疑い" },
          { "code" => "at0075", "label" => "推定" },
          { "code" => "at0076", "label" => "確定" }
        ]
      )
    end

    it "extracts the value set binding for the problem name from ProblemList" do
      source_xml = Rails.root.join("spec/fixtures/opt/ProblemList.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)
      card = result.cards.find do |candidate|
        candidate.dig("identity", "archetype_id") == "openEHR-EHR-EVALUATION.problem_diagnosis.v1" &&
          candidate.dig("identity", "at_code") == "at0002"
      end

      expect(card.dig("constraints", "value")).to eq({})
      expect(card.fetch("bindings")).to eq([
        {
          "kind" => "value_set_binding",
          "system_uri" => "terminology:http://id.who.int/icd/release/11/mms",
          "code" => nil,
          "display" => nil
        }
      ])
    end

    it "extracts the scoped SNOMED CT code binding for systolic blood pressure" do
      source_xml = Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read
      template = Template.build_from_opt_xml(source_xml)

      result = described_class.call(template)
      card = result.cards.find do |candidate|
        candidate.dig("identity", "archetype_id") == "openEHR-EHR-OBSERVATION.blood_pressure.v2" &&
          candidate.dig("identity", "at_code") == "at0004"
      end

      expect(card.fetch("bindings")).to eq(
        [
          {
            "kind" => "code_binding",
            "system_uri" => "SNOMED-CT",
            "code" => "[SNOMED-CT(2003)::271649006]",
            "display" => nil
          }
        ]
      )
    end

    golden_cards = [
      {
        fixture: "CardiologyEncounter.opt",
        identity: {
          "template_id" => "CardiologyEncounter",
          "archetype_id" => "openEHR-EHR-OBSERVATION.blood_pressure.v2",
          "path" => "/content[openEHR-EHR-OBSERVATION.blood_pressure.v2]/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value",
          "at_code" => "at0004"
        },
        semantics: {
          "rm_type" => "DV_QUANTITY",
          "container_labels" => [ { "lang" => "ja", "text" => "血圧", "archetype_id" => "openEHR-EHR-OBSERVATION.blood_pressure.v2",
                                    "untranslated_suspect" => false, "untranslated_evidence" => nil, "source_lang" => nil } ],
          "labels" => [ { "lang" => "ja", "text" => "収縮期", "untranslated_suspect" => false,
                         "untranslated_evidence" => nil, "source_lang" => nil } ],
          "descriptions" => [ { "lang" => "ja", "text" => "全身の動脈血圧での最高値 - 心機図の収縮期で測定される",
                               "untranslated_suspect" => false, "untranslated_evidence" => nil,
                               "source_lang" => nil } ]
        },
        constraints: {
          "occurrences" => { "lower" => 0, "upper" => 1 },
          "value" => {
            "property" => { "terminology" => "openehr", "code" => "125" },
            "units" => "mm[Hg]",
            "magnitude_range" => { "lower" => 0.0, "upper" => 1000.0, "lower_included" => true,
                                   "upper_included" => false },
            "precision_range" => { "lower" => 0, "upper" => 0 }
          }
        },
        bindings: [ { "kind" => "code_binding", "system_uri" => "SNOMED-CT",
                     "code" => "[SNOMED-CT(2003)::271649006]", "display" => nil } ]
      },
      {
        fixture: "LabResultReport.opt",
        identity: {
          "template_id" => "LabResultReport",
          "archetype_id" => "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1",
          "path" => "/content[openEHR-EHR-OBSERVATION.laboratory_test_result.v1]/data[at0001]/events[at0002]/data[at0003]/items[openEHR-EHR-CLUSTER.laboratory_test_analyte.v1]/items[at0001]/value",
          "at_code" => "at0001"
        },
        semantics: {
          "rm_type" => "DV_QUANTITY",
          "container_labels" => [ { "lang" => "ja", "text" => "検体検査結果", "archetype_id" => "openEHR-EHR-OBSERVATION.laboratory_test_result.v1",
                                    "untranslated_suspect" => false, "untranslated_evidence" => nil, "source_lang" => nil },
                                  { "lang" => "ja", "text" => "検査分析結果", "archetype_id" => "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1",
                                    "untranslated_suspect" => false, "untranslated_evidence" => nil, "source_lang" => nil } ],
          "labels" => [ { "lang" => "ja", "text" => "分析結果", "untranslated_suspect" => false,
                         "untranslated_evidence" => nil, "source_lang" => nil } ],
          "descriptions" => [ { "lang" => "ja", "text" => "*The value of the analyte result. (en)",
                               "untranslated_suspect" => true, "untranslated_evidence" => "fallback_marker",
                               "source_lang" => "en" } ]
        },
        constraints: {
          "occurrences" => { "lower" => 0, "upper" => nil },
          "value" => { "property" => nil, "units" => nil, "magnitude_range" => nil, "precision_range" => nil }
        },
        bindings: []
      },
      {
        fixture: "ProblemList.opt",
        identity: {
          "template_id" => "ProblemList",
          "archetype_id" => "openEHR-EHR-EVALUATION.problem_diagnosis.v1",
          "path" => "/content[openEHR-EHR-EVALUATION.problem_diagnosis.v1]/data[at0001]/items[at0002]/value",
          "at_code" => "at0002"
        },
        semantics: {
          "rm_type" => "DV_CODED_TEXT",
          "rm_type_alternatives" => [ "DV_TEXT", "DV_CODED_TEXT" ],
          "container_labels" => [ { "lang" => "ja", "text" => "プロブレム・診断", "archetype_id" => "openEHR-EHR-EVALUATION.problem_diagnosis.v1",
                                    "untranslated_suspect" => false, "untranslated_evidence" => nil, "source_lang" => nil } ],
          "labels" => [ { "lang" => "ja", "text" => "プロブレム・診断名", "untranslated_suspect" => false,
                         "untranslated_evidence" => nil, "source_lang" => nil } ],
          "descriptions" => [ { "lang" => "ja", "text" => "*Identification of the problem or diagnosis, by name. (en)",
                               "untranslated_suspect" => true, "untranslated_evidence" => "fallback_marker",
                               "source_lang" => "en" } ]
        },
        constraints: { "occurrences" => { "lower" => 1, "upper" => 1 }, "value" => {} },
        bindings: [ { "kind" => "value_set_binding",
                     "system_uri" => "terminology:http://id.who.int/icd/release/11/mms",
                     "code" => nil, "display" => nil } ]
      }
    ]

    golden_cards.each do |golden|
      it "matches the schema sample card for #{golden.fetch(:fixture)}" do
        source_xml = Rails.root.join("spec/fixtures/opt", golden.fetch(:fixture)).read
        template = Template.build_from_opt_xml(source_xml)

        card = described_class.call(template).cards.find do |candidate|
          candidate.fetch("identity") == golden.fetch(:identity)
        end

        expect(card).not_to be_nil
        expect(card.slice("schema_version", "identity", "semantics", "constraints", "bindings", "capture", "reserved")).to eq(
          "schema_version" => "1.2",
          "identity" => golden.fetch(:identity),
          "semantics" => golden.fetch(:semantics),
          "constraints" => golden.fetch(:constraints),
          "bindings" => golden.fetch(:bindings),
          "capture" => {},
          "reserved" => {}
        )
        expect(card.fetch("provenance").except("extracted_at")).to eq(
          "source_template_id" => template.template_id,
          "source_checksum" => template.checksum,
          "extractor_version" => "wp2-0.2.0"
        )
        expect { Time.iso8601(card.dig("provenance", "extracted_at")) }.not_to raise_error
      end
    end
  end

  describe "#classify_translation" do
    subject(:classification) do
      described_class.new(nil).send(:classify_translation, text)
    end

    context "when text has a fallback marker and source language" do
      let(:text) { "*Foo bar (en)" }

      it do
        expect(classification).to eq(
          "untranslated_suspect" => true,
          "untranslated_evidence" => "fallback_marker",
          "source_lang" => "en"
        )
      end
    end

    context "when unmarked text contains no Japanese script" do
      let(:text) { "Foo bar" }

      it do
        expect(classification).to eq(
          "untranslated_suspect" => true,
          "untranslated_evidence" => "no_ja_script",
          "source_lang" => nil
        )
      end
    end

    context "when text contains Japanese script" do
      let(:text) { "収縮期" }

      it do
        expect(classification).to eq(
          "untranslated_suspect" => false,
          "untranslated_evidence" => nil,
          "source_lang" => nil
        )
      end
    end
  end
end

# skoba/anlage#29（解決形 (a) bug）: SECTION 配下・protocol 配下の埋め込み
# C_ARCHETYPE_ROOT の path 述語が `items[at0000]` になっていた。content 直下と同じ
# archetype_id 述語で書くこと。fixture: spec/fixtures/opt/jp_referral.opt（real、
# 出所はファイル先頭コメント）。
RSpec.describe Opt::PathcardExtractor, "埋め込みルートの path 述語（#29）" do
  let(:cards) do
    source_xml = Rails.root.join("spec/fixtures/opt/jp_referral.opt").read
    described_class.call(Template.build_from_opt_xml(source_xml)).cards
  end

  def path_of(cards, archetype_id, at_code, index = 0)
    cards.select { |c| c.dig("identity", "archetype_id") == archetype_id && c.dig("identity", "at_code") == at_code }
         .fetch(index).dig("identity", "path")
  end

  it "SECTION 配下の ENTRY ルートを archetype_id 述語で書く" do
    expect(path_of(cards, "openEHR-EHR-INSTRUCTION.service_request.v1", "at0121")).to eq(
      "/content[openEHR-EHR-SECTION.referral_details.v0]/items[openEHR-EHR-INSTRUCTION.service_request.v1]" \
      "/activities[at0001]/description[at0009]/items[at0121]/value"
    )
  end

  it "protocol 配下に多段で埋め込まれた CLUSTER ルートも archetype_id 述語で書く（紹介先の担当医）" do
    expect(path_of(cards, "openEHR-EHR-CLUSTER.person.v1", "at0001", 1)).to eq(
      "/content[openEHR-EHR-SECTION.referral_details.v0]/items[openEHR-EHR-INSTRUCTION.service_request.v1]" \
      "/protocol[at0008]/items[openEHR-EHR-CLUSTER.organisation.v1]/items[openEHR-EHR-CLUSTER.organisation.v1]" \
      "/items[openEHR-EHR-CLUSTER.person.v1]/items[at0001]/value"
    )
  end

  it "jp_referral v0.1 の 26 カードの path に [at0000] が現れない" do
    paths = cards.map { |c| c.dig("identity", "path") }
    expect(paths.size).to eq(26)
    expect(paths.grep(/\[at0000\]/)).to be_empty
  end
end

# skoba/anlage#31（解決形 (b) enhancement、スキーマ v1.2 additive）: 祖先
# C_ARCHETYPE_ROOT（SECTION／ENTRY／CLUSTER）のテンプレート名（各ルート直下
# term_definitions の at0000 text、AD の改名を含む）を semantics.container_labels に
# ルート→葉の順で持つ。取り込み元は source_xml の再解析（gem のパース結果は
# archetype_id で畳み込まれ per-root 名を失う: openehr-ruby#58）。
RSpec.describe Opt::PathcardExtractor, "祖先ルート名 container_labels（#31、スキーマ v1.2）" do
  def cards_of(fixture)
    source_xml = Rails.root.join("spec/fixtures/opt/#{fixture}").read
    described_class.call(Template.build_from_opt_xml(source_xml)).cards
  end

  def card(cards, archetype_id, at_code, index = 0)
    cards.select { |c| c.dig("identity", "archetype_id") == archetype_id && c.dig("identity", "at_code") == at_code }.fetch(index)
  end

  def container_texts(card)
    Array(card.dig("semantics", "container_labels")).map { |entry| entry.fetch("text") }
  end

  it "schema_version を 1.2 にし、content 直下 ENTRY の葉には宿主ルート名 1 段を持つ" do
    systolic = card(cards_of("CardiologyEncounter.opt"), "openEHR-EHR-OBSERVATION.blood_pressure.v2", "at0004")

    expect(systolic.fetch("schema_version")).to eq("1.2")
    expect(systolic.dig("semantics", "container_labels")).to eq([
      { "lang" => "ja", "text" => "血圧", "archetype_id" => "openEHR-EHR-OBSERVATION.blood_pressure.v2",
        "untranslated_suspect" => false, "untranslated_evidence" => nil, "source_lang" => nil }
    ])
  end

  it "埋め込み CLUSTER の葉には宿主名と CLUSTER 名の 2 段を持つ（LabResultReport）" do
    analyte = card(cards_of("LabResultReport.opt"), "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1", "at0001")

    expect(container_texts(analyte)).to eq([ "検体検査結果", "検査分析結果" ])
  end

  it "jp_referral の紹介先担当医の氏名は SECTION→INSTRUCTION→組織→診療科→担当医の 5 段を持つ" do
    name = card(cards_of("jp_referral.opt"), "openEHR-EHR-CLUSTER.person.v1", "at0001", 1)

    expect(container_texts(name)).to eq([ "紹介状の詳細情報", "サービス依頼", "紹介先医療機関", "診療科", "担当医" ])
  end

  it "同一アーキタイプの複数ルートをテンプレート名で区別する（紹介元／紹介先／診療科の名称）" do
    cards = cards_of("jp_referral.opt")
    organisation = "openEHR-EHR-CLUSTER.organisation.v1"

    expect(container_texts(card(cards, organisation, "at0001", 0)).last).to eq("紹介元医療機関")
    expect(container_texts(card(cards, organisation, "at0001", 1)).last).to eq("紹介先医療機関")
    expect(container_texts(card(cards, organisation, "at0001", 2)).last(2)).to eq([ "紹介先医療機関", "診療科" ])
  end
end

# jp_referral v0.2（skoba/anlage#23、intake-log R10）: 傷病名 at0002 に DV_CODED_TEXT の
# 代替と ICD-11 の referenceSetUri が加わった。スキーマ v1.1 設計判断 9 の主型規約
# （コード参照を持つ代替を主型にする）が実 fixture で成立することを固定する。
# fixture 差し替え時点で既に成立している性質の固定であり Red は作れない（regression pin）。
RSpec.describe Opt::PathcardExtractor, "jp_referral v0.2 の傷病名（regression pin）" do
  let(:diagnosis) do
    source_xml = Rails.root.join("spec/fixtures/opt/jp_referral.opt").read
    described_class.call(Template.build_from_opt_xml(source_xml)).cards.find do |card|
      card.dig("identity", "archetype_id") == "openEHR-EHR-EVALUATION.problem_diagnosis.v1" && card.dig("identity", "at_code") == "at0002"
    end
  end

  it "at0002 は [DV_TEXT, DV_CODED_TEXT] の代替を持ち、主型は DV_CODED_TEXT で ICD-11 の value_set_binding を持つ" do
    expect(diagnosis.dig("semantics", "rm_type_alternatives")).to eq([ "DV_TEXT", "DV_CODED_TEXT" ])
    expect(diagnosis.dig("semantics", "rm_type")).to eq("DV_CODED_TEXT")
    expect(diagnosis.fetch("bindings")).to eq([
      { "kind" => "value_set_binding", "system_uri" => "terminology:http://id.who.int/icd/release/11/mms", "code" => nil, "display" => nil }
    ])
  end
end
