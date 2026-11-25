require "rails_helper"

RSpec.describe Opt::PathcardSearch do
  before do
    %w[CardiologyEncounter LabResultReport ProblemList].each do |name|
      source_xml = Rails.root.join("spec/fixtures/opt/#{name}.opt").read
      template = Template.build_from_opt_xml(source_xml)
      golden = JSON.parse(Rails.root.join("spec/fixtures/pathcards/#{name}.golden.json").read)
      template.pathcards = golden.fetch("cards")
      template.save!
    end
  end

  it "finds the CardiologyEncounter systolic card for 収縮期" do
    expect(identities_for(described_class.call("収縮期"))).to include(
      [ "CardiologyEncounter", "at0004" ]
    )
  end

  it "finds the shorter systolic label by bigram OR matching for 収縮期血圧" do
    expect(identities_for(described_class.call("収縮期血圧"))).to include(
      [ "CardiologyEncounter", "at0004" ]
    )
  end

  it "finds diagnostic certainty through a code-list label" do
    expect(identities_for(described_class.call("疑い"))).to include(
      [ "ProblemList", "at0073" ]
    )
  end

  it "does not bridge the BMI synonym gap" do
    # Phase 2 (embedding) の対象。docs/design/wp3-plan.md参照。
    expect(described_class.call("BMI")).to be_empty
  end

  def identities_for(results)
    results.map do |result|
      identity = result.fetch("identity")
      [ identity.fetch("template_id"), identity.fetch("at_code") ]
    end
  end
end

# skoba/anlage#31: 様式11 の欄名（AD がルートに与えた名前）で jp_referral のカードに
# 着地する。container_labels（スキーマ v1.2）を索引対象に含めること。
RSpec.describe Opt::PathcardSearch, "祖先ルート名での着地（#31）" do
  before do
    source_xml = Rails.root.join("spec/fixtures/opt/jp_referral.opt").read
    template = Template.build_from_opt_xml(source_xml)
    template.pathcards = Opt::PathcardExtractor.call(template).cards
    template.save!
  end

  def jp_referral_hits(query)
    described_class.call(query).select { |card| card.dig("identity", "template_id") == "jp_referral" }
                   .map { |card| card.dig("identity").values_at("archetype_id", "at_code") }
  end

  it "既往歴 → story の病歴の記述" do
    expect(jp_referral_hits("既往歴")).to include([ "openEHR-EHR-OBSERVATION.story.v1", "at0004" ])
  end

  it "傷病名 → problem_diagnosis のプロブレム・診断の名称" do
    expect(jp_referral_hits("傷病名")).to include([ "openEHR-EHR-EVALUATION.problem_diagnosis.v1", "at0002" ])
  end

  it "治療経過 → clinical_synopsis の要約" do
    expect(jp_referral_hits("治療経過")).to include([ "openEHR-EHR-EVALUATION.clinical_synopsis.v1", "at0002" ])
  end

  it "紹介先 → 紹介先医療機関の名称" do
    expect(jp_referral_hits("紹介先")).to include([ "openEHR-EHR-CLUSTER.organisation.v1", "at0001" ])
  end
end

# skoba/anlage#32（解決形 (a)、裁定 2026-09-25）: 検索索引は active 版のテンプレートの
# カードのみ。superseded 版のカードは系譜・diff 用に保持したまま索引から外す
# （v0.1／v0.2 の同一カードがデモの検索結果に並ばないようにする）。
RSpec.describe Opt::PathcardSearch, "superseded 版は索引しない（#32）" do
  it "同一 template_id の旧版（superseded）のカードは結果に現れず、active 版だけがヒットする" do
    xml = Rails.root.join("spec/fixtures/opt/jp_referral.opt").read
    old_version = Template.build_from_opt_xml(xml)
    old_version.pathcards = Opt::PathcardExtractor.call(old_version).cards
    old_version.checksum = "0" * 64 # 旧版として別 checksum で登録
    old_version.save!
    new_version = Template.build_from_opt_xml(xml)
    new_version.version = "1.0.1"
    new_version.pathcards = Opt::PathcardExtractor.call(new_version).cards
    new_version.save!
    old_version.supersede!

    hits = described_class.call("既往歴").select { |card| card.dig("identity", "template_id") == "jp_referral" }

    expect(hits.size).to eq(1)
    expect(hits.first.dig("provenance", "source_checksum")).to eq(new_version.checksum)
  end
end

RSpec.describe Opt::PathcardSearch, "ELEMENT 改名がラベルとして検索に効く（per-instance term）" do
  before do
    template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/jp_referral.opt").read)
    template.pathcards = Opt::PathcardExtractor.call(template).cards
    template.save!
  end

  it "「症状経過及び検査結果」「治療経過」が要素ラベルとして着地する（container ではなく labels 経由）" do
    %w[症状経過及び検査結果 治療経過].each do |query|
      hit = described_class.call(query).find { |c| c.dig("semantics", "labels", 0, "text") == query }
      expect(hit).not_to be_nil, "#{query} が labels でヒットしない"
      expect(hit.dig("identity", "archetype_id")).to eq("openEHR-EHR-EVALUATION.clinical_synopsis.v1")
    end
  end
end

# skoba/anlage#122（S3 の段 A。docs/design/s3-search-plan.md 3 節、R-20261125-2）: 同点のカードの順序を、
# テンプレートの登録順ではなく、template_id と、テンプレートの中でのカードの並びで決める。
# 「発症」は、ProblemList と jp_referral の「発症日時」（同じアーキタイプの同じ節）がラベルに当たって同点になる。
# （はじめは「臨床検査」の 4 枚の同点で固定していた。項目の重み〔#127〕で同点でなくなったので、問いを替えた）
RSpec.describe Opt::PathcardSearch, "同点の順序は登録順によらない（#122）" do
  def register(fixture_names)
    fixture_names.each do |fixture_name|
      template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture_name}.opt").read)
      template.pathcards = Opt::PathcardExtractor.call(template).cards
      template.save!
    end
  end

  def hits(query)
    described_class.call(query).map { |card| [ card.fetch("score"), *card.fetch("identity").values_at("template_id", "at_code") ] }
  end

  it "同じテンプレートを別の順で登録しても、同じ並びを返す" do
    register(%w[ProblemList jp_referral])
    first_order = hits("発症")
    Template.delete_all
    register(%w[jp_referral ProblemList])

    expect(hits("発症")).to eq(first_order)
  end

  it "同点は template_id の順に並べる" do
    register(%w[jp_referral ProblemList])

    expect(hits("発症")).to eq([ [ 4, "ProblemList", "at0077" ], [ 4, "jp_referral", "at0077" ] ])
  end

  it "同じテンプレートの中の同点は、カードの並び（帳票の順）で並べる" do
    register(%w[LabResultReport])

    expect(hits("分析")).to eq([ [ 7, "LabResultReport", "at0024" ], [ 7, "LabResultReport", "at0001" ] ])
  end

  it "score の高いカードは、template_id が後ろでも先に出る" do
    register(%w[CardiologyEncounter ProblemList])
    results = hits("発症日時")

    expect(results.map(&:first)).to eq(results.map(&:first).sort.reverse)
    expect(results.first).to eq([ 12, "ProblemList", "at0077" ])
  end
end

# skoba/anlage#127（S3 の段 B。docs/design/s3-search-plan.md 3 節）: score に、当たった項目の重みを入れる。
# 問いの bigram ごとに、それを含む項目の重みを足す（ラベル 4、いちばん近い祖先の名前 3、それより遠い祖先の名前 2、
# 値集合の表示 2、説明 1）。
RSpec.describe Opt::PathcardSearch, "項目の重み（#127）" do
  before do
    %w[ProblemList LabResultReport].each do |fixture_name|
      template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture_name}.opt").read)
      template.pathcards = Opt::PathcardExtractor.call(template).cards
      template.save!
    end
  end

  def hits(query)
    described_class.call(query).map { |card| [ card.dig("identity", "at_code"), card.fetch("score") ] }
  end

  it "ラベルに当たったカードは、祖先の名前だけに当たったカードより前に出る（診断）" do
    # 祖先の名前「プロブレム・診断」は 6 枚すべてに当たる（3）。ラベルにも当たるのは at0002 と at0073（3 + 4）
    expect(hits("診断").first(3)).to eq([ [ "at0002", 7 ], [ "at0073", 7 ], [ "at0077", 3 ] ])
  end

  it "ラベルと祖先の名前の両方に当たる bigram は、両方の重みを足す（検査結果）" do
    # at0001「分析結果」: ラベル「結果」4、祖先「検体検査結果」（遠い）と「検査分析結果」（近い）の「検査」「結果」(2 + 3) × 2、「査結」は遠い祖先だけ 2
    expect(hits("検査結果")).to eq([ [ "at0001", 16 ], [ "at0005", 13 ], [ "at0024", 12 ] ])
  end

  it "値集合の表示だけに当たるカードも出る（疑い）" do
    expect(hits("疑い")).to eq([ [ "at0073", 2 ] ])
  end

  it "「臨床検査」は、祖先の名前 2 つに当たる 2 枚（2 + 3）が、ラベル 1 つに当たる負例（4）より前に出る" do
    expect(hits("臨床検査")).to eq([ [ "at0005", 7 ], [ "at0024", 5 ], [ "at0001", 5 ], [ "at0003", 4 ] ])
  end
end

# skoba/anlage#152（S3 の段 D。docs/design/s3-search-plan.md 3.1、R-20261125-8）: 別名表。
# 問いの語の全体が表の語に一致したときだけ、対応先のカードを字面の結果より前に出す。対応させない行は、対応先を結果から外す。
RSpec.describe Opt::PathcardSearch, "別名表（#152）" do
  PS_PD = "openEHR-EHR-EVALUATION.problem_diagnosis.v1".freeze
  PS_BMI = "openEHR-EHR-OBSERVATION.body_mass_index.v2".freeze
  PS_LAB = "openEHR-EHR-OBSERVATION.laboratory_test_result.v1".freeze

  before do
    %w[ProblemList LabResultReport bmi_calculation].each do |fixture_name|
      template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture_name}.opt").read)
      template.pathcards = Opt::PathcardExtractor.call(template).cards
      template.save!
    end
  end

  def aliases(*rows)
    Opt::SearchAliases.new(rows.map do |row|
      { "relation" => "alias", "source" => "spec", "reviewed_by" => "Kobayashi, Shinji", "reviewed_at" => Date.new(2026, 11, 25) }.merge(row.transform_keys(&:to_s))
    end)
  end

  def hits(query, table)
    described_class.call(query, aliases: table).map { |card| [ *card.fetch("identity").values_at("archetype_id", "at_code"), card.fetch("score"), card["alias"] ] }
  end

  it "字面で 1 つも当たらない語（病名）でも、対応先のカードが出る。カードは alias に語を持ち、score は字面の値（0）" do
    table = aliases({ term: "病名", targets: [ { "archetype_id" => PS_PD, "at_code" => "at0002" } ] })

    expect(hits("病名", Opt::SearchAliases.none)).to eq([])
    expect(hits("病名", table)).to eq([ [ PS_PD, "at0002", 0, "病名" ] ])
  end

  it "対応先の順に出す。同じ対応先の中は、字面の score、同点の規則の順（既往: at0002 が先、残りは帳票の順）" do
    table = aliases({ term: "既往", targets: [ { "archetype_id" => PS_PD, "at_code" => "at0002" }, { "archetype_id" => PS_PD } ] })

    expect(hits("既往", table).map { |hit| hit[1] }).to eq(%w[at0002 at0077 at0003 at0030 at0073 at0070])
  end

  it "別名で当たったカードは、字面で当たったカードより前に出る。字面の結果は、そのあとに残る（臨床検査）" do
    table = aliases({ term: "臨床検査", targets: [ { "archetype_id" => PS_LAB } ] })

    expect(hits("臨床検査", table)).to eq([
      [ PS_LAB, "at0005", 7, "臨床検査" ],
      [ "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1", "at0024", 5, nil ],
      [ "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1", "at0001", 5, nil ],
      [ PS_PD, "at0003", 4, nil ]
    ])
  end

  it "語の全体が一致したときだけ引く（「既往歴」は「既往」の行に当たらない）。全角と半角、英字の大小は区別しない（ｂｍｉ）" do
    table = aliases({ term: "既往", targets: [ { "archetype_id" => PS_PD } ] }, { term: "BMI", targets: [ { "archetype_id" => PS_BMI } ] })

    expect(hits("既往歴", table)).to eq([])
    expect(hits("ｂｍｉ", table).map { |hit| hit[1] }).to eq(%w[at0004 at0013])
  end

  it "対応させない行（exclude）: その語では、対応先のカードを結果から外す。ほかの語（BMI判定）には効かない" do
    table = aliases({ term: "判定", relation: "exclude", targets: [ { "archetype_id" => PS_BMI, "at_code" => "at0013" } ] })

    expect(hits("判定", Opt::SearchAliases.none).map { |hit| hit[1] }).to eq([ "at0013" ])
    expect(hits("判定", table)).to eq([])
    expect(hits("BMI判定", table).map { |hit| hit[1] }).to include("at0013")
  end

  it "索引に無い対応先は、黙って読み飛ばす" do
    table = aliases({ term: "病名", targets: [ { "archetype_id" => "openEHR-EHR-OBSERVATION.story.v1", "at_code" => "at0004" }, { "archetype_id" => PS_PD, "at_code" => "at0002" } ] })

    expect(hits("病名", table).map { |hit| hit[1] }).to eq([ "at0002" ])
  end

  it "aliases を渡さなければ、リポジトリの表（config/search_aliases.yml）を使う" do
    expect(described_class.call("BMI").map { |card| card.dig("identity", "at_code") }).to eq(%w[at0004 at0013])
    expect(described_class.call("体格指数")).to eq([])
  end
end
