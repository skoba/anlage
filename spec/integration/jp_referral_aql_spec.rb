require "rails_helper"

# skoba/anlage#23 (4): 「MML 1 通・JP-CLINS 1 通の手動写像から同じ AQL で引ける」。
# 経路はフォーム保存（#30）ではなく直接コミット（手写像 canonical JSON →
# OpenehrRails::Rm::CompositionCommitter → AQL、裁定 C）。
#
# 残る待ちは 1 つ:
#   - skip: 手写像元 fixture が未供給（spec/fixtures/compositions/jp_referral/README.md）
# name 述語（`, '紹介先医療機関'`）は openehr 2.5.0（openehr-ruby#60、上流候補 24 項）で効くようになり、
# pending を外した（2026-11-24、skoba/anlage#90）。
# 紹介日（context/start_time）は 16 項（EVENT_CONTEXT 未永続化）により含めない。
RSpec.describe "jp_referral: 手動写像 Composition からの AQL 統一性（#23 (4)）" do
  FIXTURE_DIR = Rails.root.join("spec/fixtures/compositions/jp_referral")

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

      commit(JSON.parse(path.read))
      result = OpenehrRails::Aql::Executor.execute(RECEIVER_AQL)

      expect(result.rows.size).to eq(1)
      expect(result.rows.first).to all(be_present)
    end
  end

  # 構造骨格（fixture 種別: synthetic skeleton。at-code は jp_referral.opt の実物、値は作例、
  # 臨床文書ではない。docs/reports/referral-intake-log.md R6 の変種 4 と同形）。
  # 手写像元が届く前から「直接コミット経路＋name 述語の AQL」自体を固定する。
  # fixture は rake demo:reset のサンプルと共有
  # （spec/fixtures/compositions/jp_referral/skeleton.canonical.json）。
  it "構造骨格（実 at-code）を直接コミットし、紹介先医療機関を name 述語で引ける" do
    commit(JSON.parse(FIXTURE_DIR.join("skeleton.canonical.json").read))
    result = OpenehrRails::Aql::Executor.execute(RECEIVER_AQL)

    expect(result.rows).to eq([ [ "X病院", "2型糖尿病" ] ])
  end
end
