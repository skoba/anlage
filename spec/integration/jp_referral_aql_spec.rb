require "rails_helper"

# skoba/anlage#23 (4): 「MML 1 通・JP-CLINS 1 通の手動写像から同じ AQL で引ける」。
# 経路はフォーム保存（#30）ではなく直接コミット（手写像 canonical JSON →
# OpenehrRails::Rm::CompositionCommitter → AQL、裁定 C）。
#
# 現状は 2 段の待ちを spec の形で正直に表す:
#   - skip:    手写像元 fixture が未供給（spec/fixtures/compositions/jp_referral/README.md）
#   - pending: openehr-rails 上流候補 15 項（RmObjectBuilder::TYPE_CLASSES に SECTION／
#              INSTRUCTION／ACTIVITY が無く、含む Composition の to_rm が
#              NoMethodError になり store 全体の AQL が失敗する）の解消待ち。
#              解消後は pending の example が「通ってしまう」ので RSpec が失敗として
#              知らせる → pending を外す。
# 紹介日（context/start_time）は 16 項（EVENT_CONTEXT 未永続化）により含めない。
RSpec.describe "jp_referral: 手動写像 Composition からの AQL 統一性（#23 (4)）" do
  FIXTURE_DIR = Rails.root.join("spec/fixtures/compositions/jp_referral")
  UPSTREAM_15 = "openehr-rails 上流候補 15 項（SECTION/INSTRUCTION の to_rm）の解消待ち"

  RECEIVER_AQL = <<~AQL
    SELECT i/protocol[at0008]/items[openEHR-EHR-CLUSTER.organisation.v1, '紹介先医療機関']/items[at0001]/value/value AS receiver,
           ev/data[at0001]/items[at0002]/value/value AS diagnosis
    FROM EHR e CONTAINS COMPOSITION c[openEHR-EHR-COMPOSITION.request.v1]
         CONTAINS (INSTRUCTION i[openEHR-EHR-INSTRUCTION.service_request.v1]
                   AND EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1])
  AQL

  def commit(hash)
    OpenehrRails::Rm::CompositionCommitter.commit(hash, uid: SecureRandom.uuid, owner: nil)
  end

  {
    "MML 紹介状 1 通" => "mml-case1.canonical.json",
    "JP-CLINS Bundle 1 通" => "jpclins-case1.canonical.json"
  }.each do |source, file|
    it "#{source} の手写像 Composition を直接コミットし、紹介先医療機関と傷病名を同じ AQL で引ける" do
      path = FIXTURE_DIR.join(file)
      skip "手写像元（#{source}）未供給: #{file} が無い（裁定 C、人間供給待ち）" unless path.exist?
      pending UPSTREAM_15

      commit(JSON.parse(path.read))
      result = OpenehrRails::Aql::Executor.execute(RECEIVER_AQL)

      expect(result.rows.size).to eq(1)
      expect(result.rows.first).to all(be_present)
    end
  end

  # 構造骨格（fixture 種別: synthetic skeleton。at-code は jp_referral.opt の実物、値は作例、
  # 臨床文書ではない。docs/reports/referral-intake-log.md R6 の変種 4 と同形）。
  # 手写像元が届く前から「直接コミット経路＋name 述語の AQL」自体を固定し、上流 15 項の
  # 解消をこの example の pending 解除で検知する。
  it "構造骨格（実 at-code）を直接コミットし、紹介先医療機関を name 述語で引ける" do
    pending UPSTREAM_15

    commit(skeleton_composition)
    result = OpenehrRails::Aql::Executor.execute(RECEIVER_AQL)

    expect(result.rows).to eq([ [ "X病院", "2型糖尿病" ] ])
  end

  def dv_text(value) = { "_type" => "DV_TEXT", "value" => value }
  def element(at, name, value) = { "_type" => "ELEMENT", "archetype_node_id" => at, "name" => dv_text(name), "value" => value }

  def archetyped(archetype_id)
    { "_type" => "ARCHETYPED", "archetype_id" => { "_type" => "ARCHETYPE_ID", "value" => archetype_id },
      "rm_version" => "1.0.4", "template_id" => { "_type" => "TEMPLATE_ID", "value" => "jp_referral" } }
  end

  def organisation(name, org_name, items = [])
    { "_type" => "CLUSTER", "archetype_node_id" => "openEHR-EHR-CLUSTER.organisation.v1", "name" => dv_text(name),
      "archetype_details" => archetyped("openEHR-EHR-CLUSTER.organisation.v1"),
      "items" => [ element("at0001", "名称", dv_text(org_name)) ] + items }
  end

  def skeleton_composition
    { "_type" => "COMPOSITION", "archetype_node_id" => "openEHR-EHR-COMPOSITION.request.v1", "name" => dv_text("jp_referral"),
      "archetype_details" => archetyped("openEHR-EHR-COMPOSITION.request.v1"),
      "language" => { "_type" => "CODE_PHRASE", "code_string" => "ja", "terminology_id" => { "_type" => "TERMINOLOGY_ID", "value" => "ISO_639-1" } },
      "territory" => { "_type" => "CODE_PHRASE", "code_string" => "JP", "terminology_id" => { "_type" => "TERMINOLOGY_ID", "value" => "ISO_3166-1" } },
      "category" => { "_type" => "DV_CODED_TEXT", "value" => "event", "defining_code" => { "_type" => "CODE_PHRASE", "code_string" => "433", "terminology_id" => { "_type" => "TERMINOLOGY_ID", "value" => "openehr" } } },
      "composer" => { "_type" => "PARTY_IDENTIFIED", "name" => "unknown" },
      "content" => [
        { "_type" => "SECTION", "archetype_node_id" => "openEHR-EHR-SECTION.referral_details.v0", "name" => dv_text("紹介状の詳細情報"),
          "archetype_details" => archetyped("openEHR-EHR-SECTION.referral_details.v0"),
          "items" => [
            { "_type" => "INSTRUCTION", "archetype_node_id" => "openEHR-EHR-INSTRUCTION.service_request.v1", "name" => dv_text("サービス依頼"),
              "archetype_details" => archetyped("openEHR-EHR-INSTRUCTION.service_request.v1"), "narrative" => dv_text("精査依頼"),
              "activities" => [ { "_type" => "ACTIVITY", "archetype_node_id" => "at0001", "name" => dv_text("現在のアクティビティ"), "action_archetype_id" => "/.*/",
                                  "description" => { "_type" => "ITEM_TREE", "archetype_node_id" => "at0009", "name" => dv_text("Tree"),
                                                     "items" => [ element("at0121", "サービス名", dv_text("外来紹介")), element("at0062", "紹介目的", dv_text("精査加療のお願い")) ] } } ],
              "protocol" => { "_type" => "ITEM_TREE", "archetype_node_id" => "at0008", "name" => dv_text("Tree"),
                              "items" => [ organisation("紹介元医療機関", "Aクリニック"), organisation("紹介先医療機関", "X病院", [ organisation("診療科", "内科") ]) ] } },
            { "_type" => "EVALUATION", "archetype_node_id" => "openEHR-EHR-EVALUATION.problem_diagnosis.v1", "name" => dv_text("傷病名"),
              "archetype_details" => archetyped("openEHR-EHR-EVALUATION.problem_diagnosis.v1"),
              "data" => { "_type" => "ITEM_TREE", "archetype_node_id" => "at0001", "name" => dv_text("structure"),
                          "items" => [ element("at0002", "プロブレム・診断の名称", dv_text("2型糖尿病")) ] } }
          ] }
      ] }
  end
end
