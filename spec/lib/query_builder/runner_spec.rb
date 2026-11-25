require "rails_helper"

# 組む → リンタ → 実行（docs/design/s2-query-builder-plan.md 6.3）。データは demo_initial（rake demo:reset の初期状態）。
# 期待する行は、評価 v2 のゴールド（spec/fixtures/evaluation/v2/aql.yml、臨床レビュー済み）の a001〜a005 の期待行と同じ。
RSpec.describe QueryBuilder::Runner do
  QB_BP_O = "openEHR-EHR-OBSERVATION.blood_pressure.v2".freeze
  QB_PD_E = "openEHR-EHR-EVALUATION.problem_diagnosis.v1".freeze
  QB_ANALYTE_C = "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1".freeze
  QB_HEIGHT_O = "openEHR-EHR-OBSERVATION.height.v2".freeze

  before { Evaluation::Datasets.build("demo_initial") }

  let(:corpus) { QueryBuilder::Corpus.active }
  let(:gold) { Evaluation::Questions.from_v2.index_by(&:id) }

  def card(archetype_id, at_code)
    corpus.cards.find { |candidate| candidate["identity"].values_at("archetype_id", "at_code") == [ archetype_id, at_code ] } ||
      raise("カードが無い: #{archetype_id} #{at_code}")
  end

  def rows(run)
    run.rows.map { |row| row.map { |value| value.is_a?(Numeric) ? value.to_f : value } }
  end

  it "a001〜a005 と同じ選択を組んで実行すると、ゴールドの期待行と同じ行を返す（リンタの error なし）" do
    selections = {
      "a001" => { columns: [ card(QB_BP_O, "at0004") ], conditions: [ { card: card(QB_BP_O, "at0004"), operator: ">", value: "110" } ] },
      "a002" => { columns: [ card(QB_PD_E, "at0002") ], conditions: [ { card: card(QB_PD_E, "at0073"), operator: "MATCHES", value: [ "at0074" ] } ] },
      "a003" => { columns: [ card(QB_PD_E, "at0002") ], composition_name: true,
                  conditions: [ { card: card(QB_PD_E, "at0002"), operator: "MATCHES", value: [ "2型糖尿病", "高血圧症" ] } ] },
      "a004" => { columns: [ card(QB_ANALYTE_C, "at0001") ], conditions: [ { card: card(QB_ANALYTE_C, "at0024"), operator: "=", value: "空腹時血糖" } ] },
      "a005" => { columns: [ card(QB_HEIGHT_O, "at0004") ], conditions: [ { card: card(QB_HEIGHT_O, "at0004"), operator: ">=", value: "170" } ] }
    }

    selections.each do |id, selection|
      run = described_class.call(**selection)

      expect(run).to have_attributes(executed?: true, error: nil), "#{id}: #{run.error}\n#{run.aql}"
      expect(run.lint.findings.select(&:error?)).to be_empty
      expect(rows(run)).to match_array(gold.fetch(id).expected_rows), id
      expect(Evaluation::AqlScorer.score(gold.fetch(id), aql: run.aql).status).to eq(:match), id
    end
  end

  it "組めない選択は実行せず、理由を error に持つ（AQL は無い）" do
    run = described_class.call(columns: [])

    expect(run).to have_attributes(executed?: false, aql: nil, rows: [])
    expect(run.error).to include("表示する項目")
  end

  it "リンタの error がある AQL は実行しない（索引から消えたアーキタイプのカード）" do
    stale = card(QB_BP_O, "at0004")
    Template.where(template_id: "CardiologyEncounter").destroy_all

    run = described_class.call(columns: [ stale ])

    expect(run).to have_attributes(executed?: false, rows: [])
    expect(run.aql).to include(QB_BP_O)
    expect(run.lint.findings.select(&:error?).map(&:code)).to eq([ :path ])
  end

  it "execute: false なら、組んでリンタを通すところまで（プレビュー）" do
    run = described_class.call(columns: [ card(QB_BP_O, "at0004") ], execute: false)

    expect(run).to have_attributes(executed?: false, error: nil, rows: [])
    expect(run.lint.ok?).to be(true)
    expect(run.aql).to start_with("SELECT o/data[at0001]")
  end
  # docs/design/s2-query-builder-plan.md 7 節（R-20261125-6）。demo_initial の傷病は 3 件（高血圧症〔疑い〕、2型糖尿病〔疑い〕、
  # 2型糖尿病〔確度の記載なし〕）、血圧は 1 件（120／80）。値集合のコードは at0074＝疑い、at0076＝確定
  describe "未記入を含む、範囲の外、どちらかを満たす" do
    def run(**selection)
      described_class.call(**selection).tap do |result|
        expect(result).to have_attributes(executed?: true, error: nil), "#{result.error}\n#{result.aql}"
        expect(result.lint.findings.select(&:error?)).to be_empty
      end
    end

    it "未記入を含む: 「確定」だけでは 0 行、未記入を含めると確度の記載が無い 1 行。「疑い」に未記入を含めると 3 行" do
      diagnosis = card(QB_PD_E, "at0002")
      certainty = card(QB_PD_E, "at0073")

      expect(rows(run(columns: [ diagnosis ], conditions: [ { card: certainty, operator: "MATCHES", value: [ "at0076" ] } ]))).to eq([])
      expect(rows(run(columns: [ diagnosis ], conditions: [ { card: certainty, operator: "MATCHES", value: [ "at0076" ], include_missing: true } ])))
        .to eq([ [ "2型糖尿病" ] ])
      expect(rows(run(columns: [ diagnosis ], conditions: [ { card: certainty, operator: "MATCHES", value: [ "at0074" ], include_missing: true } ])))
        .to match_array([ [ "高血圧症" ], [ "2型糖尿病" ], [ "2型糖尿病" ] ])
    end

    it "範囲の外: 収縮期 120 は、100〜110 の外（1 行）で、90〜140 の中（0 行）" do
      systolic = card(QB_BP_O, "at0004")

      expect(rows(run(columns: [ systolic ], conditions: [ { card: systolic, operator: "OUTSIDE", value: { low: 100, high: 110 } } ]))).to eq([ [ 120.0 ] ])
      expect(rows(run(columns: [ systolic ], conditions: [ { card: systolic, operator: "OUTSIDE", value: { low: 90, high: 140 } } ]))).to eq([])
    end

    it "どちらかを満たす: 収縮期 >= 140 または拡張期 >= 80 は 1 行（拡張期で当たる）。どちらも外れると 0 行。ほかの条件とは AND" do
      systolic = card(QB_BP_O, "at0004")
      diastolic = card(QB_BP_O, "at0005")
      either = ->(low) { { any: [ { card: systolic, operator: ">=", value: "140" }, { card: diastolic, operator: ">=", value: low } ] } }

      expect(rows(run(columns: [ systolic, diastolic ], conditions: [ either.call("80") ]))).to eq([ [ 120.0, 80.0 ] ])
      expect(rows(run(columns: [ systolic, diastolic ], conditions: [ either.call("90") ]))).to eq([])
      expect(rows(run(columns: [ systolic, diastolic ], conditions: [ either.call("80"), { card: systolic, operator: ">", value: "200" } ]))).to eq([])
    end
  end

end
