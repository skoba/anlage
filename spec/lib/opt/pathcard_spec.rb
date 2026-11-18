require "rails_helper"

# アーキタイプパス（skoba/anlage#64、裁定 R-20261116-1）: identity.path のうち、所属アーキタイプの
# 述語 [<archetype_id>] の最後の出現より後ろ。表示用の導出値で、スキーマ v1.2 と golden は変えない。
# 期待値は golden（CKM 由来の実物 OPT からの抽出結果）の identity.path からの実測。
RSpec.describe Opt::Pathcard do
  describe ".archetype_path" do
    it "content 直下のアーキタイプ: ProblemList の プロブレム・診断名（at0002）" do
      card = golden_card("ProblemList", "openEHR-EHR-EVALUATION.problem_diagnosis.v1", "at0002")

      expect(described_class.archetype_path(card)).to eq("/data[at0001]/items[at0002]/value")
    end

    it "埋め込み CLUSTER は CLUSTER を根とした相対パス: LabResultReport の 分析結果（at0001）" do
      card = golden_card("LabResultReport", "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1", "at0001")

      expect(described_class.archetype_path(card)).to eq("/items[at0001]/value")
    end

    it "SECTION 配下の ENTRY: jp_referral の 傷病名（problem_diagnosis at0002）" do
      card = golden_card("jp_referral", "openEHR-EHR-EVALUATION.problem_diagnosis.v1", "at0002")

      expect(described_class.archetype_path(card)).to eq("/data[at0001]/items[at0002]/value")
    end

    it "同じアーキタイプの入れ子は最後の出現より後ろ: jp_referral の 紹介先医療機関 内 診療科（organisation at0001）" do
      predicate = "[openEHR-EHR-CLUSTER.organisation.v1]"
      card = golden_card("jp_referral", "openEHR-EHR-CLUSTER.organisation.v1", "at0001") do |candidate|
        candidate.dig("identity", "path").scan(predicate).size == 2
      end

      expect(described_class.archetype_path(card)).to eq("/items[at0001]/value")
    end

    it "述語が path に現れないカードは nil（fixture OPT 6 件・44 カードに該当は無く、合成カードで固定）" do
      card = { "identity" => { "archetype_id" => "openEHR-EHR-EVALUATION.problem_diagnosis.v1",
                               "path" => "/data[at0001]/items[at0002]/value" } }

      expect(described_class.archetype_path(card)).to be_nil
    end
  end

  # ブロックは同じ (archetype_id, at_code) のカードが複数あるときの絞り込み（organisation は 3 枚）。
  def golden_card(template_id, archetype_id, at_code, &narrow)
    cards = JSON.parse(Rails.root.join("spec/fixtures/pathcards/#{template_id}.golden.json").read).fetch("cards")
    matches = cards.select do |card|
      card.fetch("identity").values_at("archetype_id", "at_code") == [ archetype_id, at_code ]
    end
    matches = matches.select(&narrow) if narrow
    expect(matches.size).to eq(1)
    matches.first
  end
end
