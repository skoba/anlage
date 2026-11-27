require "rails_helper"

# 測定に使う問いの文を読み、正解の行を、決まりどおりに引く（spec/fixtures/evaluation/nl/nl_queries.yml の冒頭。計画書 12 節）
RSpec.describe Evaluation::Grounding::Queries do
  let(:queries) { described_class.load.index_by(&:id) }

  it "測定に使う文は 37。調整用（tuning）は読まない" do
    expect(queries.size).to eq(37)
    expect(queries.keys).not_to include("t001")
  end

  it "自前の expected_rows を持つ問い（名指し、検査）は、それが正解。見落としは見ない" do
    expect(queries["n001-4"].expected_rows).to eq([ [ 148.0 ], [ 152.0 ] ])
    expect(queries["n001-4"].partial_rows).to be_nil
    expect(queries["n101-2"].expected_rows).to eq([ [ 9.8 ], [ 8.9 ], [ 9.4 ] ])
    expect(queries["n101-2"].tags).to eq(%w[abbrev value_paraphrase])
  end

  it "名指ししない血圧の問いは、v1 と v2 の両方を引いた行が正解。片方の版だけの行を、見落としとして持つ" do
    query = queries["n001-1"]

    expect(query.expected_rows).to match_array([ [ 162.0 ], [ 158.0 ], [ 146.0 ], [ 142.0 ], [ 148.0 ], [ 152.0 ] ])
    expect(query.partial_rows.keys).to eq(%w[openEHR-EHR-OBSERVATION.blood_pressure.v1 openEHR-EHR-OBSERVATION.blood_pressure.v2])
    expect(query).to be_both_versions
    expect(query).to be_overlook_measurable
  end

  it "a009 の文は、v1 に当たる記録が無いので、見落としを見分けられない（母数から外す）" do
    expect(queries["n009-1"]).to be_both_versions
    expect(queries["n009-1"]).not_to be_overlook_measurable
    expect(queries["n009-1"].expected_rows).to eq([ [ 88.0, 54.0 ], [ 96.0, 60.0 ] ])
  end

  it "それ以外は、もとの問い（v2 のゴールド）の expected_rows" do
    expect(queries["n002-2"].expected_rows.size).to eq(7)
    expect(queries["n013-2"].expected_rows.first).to eq([ "ProblemList", "糖尿病性腎症", "2025-10-01T00:00:00Z" ])
    expect(queries["n002-2"]).not_to be_both_versions
  end

  it "版をまたぐ問い（a014 の文）は、選択を出す腕だけで数える。正解の行は、版の列を持つ" do
    expect(queries["n014-1"]).to be_selection_only
    expect(queries["n014-1"].expected_rows.first.first).to eq("openEHR-EHR-OBSERVATION.blood_pressure.v1")
    expect(queries["n001-1"]).not_to be_selection_only
  end

  it "問いが指すカード（カードの一致の採点に使う）を持つ" do
    expect(queries["n002-1"].cards).to match_array([
      { archetype_id: "openEHR-EHR-EVALUATION.problem_diagnosis.v1", at_code: "at0073" },
      { archetype_id: "openEHR-EHR-EVALUATION.problem_diagnosis.v1", at_code: "at0002" }
    ])
    expect(queries["n102-1"].cards.map { |card| card[:at_code] }).to match_array(%w[at0001 at0024])
  end

  it "問いのファイルの sha256 を答える（測定の記録に入れる）" do
    expect(described_class.sha256).to eq(Digest::SHA256.file(Rails.root.join(described_class::PATH)).hexdigest)
  end
end
