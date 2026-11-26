require "rails_helper"

# 版をまたいで引く（docs/design/s2-cross-version-plan.md 4 節、skoba/anlage#154、R-20261125-10）。
# データは demo_initial（血圧は blood_pressure.v2 の 120／80 が 1 件）に、blood_pressure.v1 の記録（150／95、100／60）を足したもの。
# 対応の表は、この spec の中で行を作って渡す（リポジトリの表に左右されないように）。リポジトリの表を使う例は最後に 1 つ。
RSpec.describe "版をまたいで引く" do
  XV_BP = "openEHR-EHR-OBSERVATION.blood_pressure".freeze
  XV_PD = "openEHR-EHR-EVALUATION.problem_diagnosis.v1".freeze

  before do
    Evaluation::Datasets.build("demo_initial")
    template = Template.active.find_by!(template_id: "patient_blood_pressure.v1")
    [ %w[150 95], %w[100 60] ].each do |systolic, diastolic|
      commit = Opt::RmCompositionCommitter.call(template, { "blood_pressure_systolic" => systolic, "blood_pressure_diastolic" => diastolic })
      template.compositions.create!(rm_composition: commit.canonical_hash, uid: commit.uid)
    end
  end

  let(:corpus) { QueryBuilder::Corpus.active }

  def card(archetype_id, at_code)
    corpus.cards.find { |candidate| candidate["identity"].values_at("archetype_id", "at_code") == [ archetype_id, at_code ] } ||
      raise("カードが無い: #{archetype_id} #{at_code}")
  end

  def mappings(*at_codes, status: "active")
    QueryBuilder::VersionMappings.new(at_codes.map do |at_code|
      { "concept" => XV_BP, "at_code" => at_code, "versions" => %w[v1 v2], "status" => status, "source" => "spec",
        "reviewed_by" => "Kobayashi, Shinji", "reviewed_at" => Date.new(2026, 11, 25) }
    end)
  end

  let(:systolic) { card("#{XV_BP}.v2", "at0004") }
  let(:diastolic) { card("#{XV_BP}.v2", "at0005") }
  let(:both) { mappings("at0004", "at0005") }

  def run(**selection)
    QueryBuilder::Runner.call(across_versions: true, **selection)
  end

  def rows(result)
    result.rows.map { |row| row.map { |value| value.is_a?(Numeric) ? value.to_f : value } }
  end

  it "版ごとに AQL を組む。違うのはアーキタイプの述語の版だけ" do
    result = run(columns: [ systolic ], conditions: [ { card: systolic, operator: ">=", value: "140" } ], mappings: both, execute: false)

    path = "o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude"
    expect(result.queries.map(&:archetype_id)).to eq([ "#{XV_BP}.v1", "#{XV_BP}.v2" ])
    expect(result.queries.map(&:aql)).to eq(%w[v1 v2].map do |version|
      "SELECT #{path}\nFROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[#{XV_BP}.#{version}]\nWHERE #{path} >= 140"
    end)
    expect(result.lint.ok?).to be(true)
    expect(result).to have_attributes(executed?: false, version_column?: true)
  end

  it "v1 と v2 の記録を 1 つの結果にまとめ、先頭の列に、行が来たアーキタイプの ID（版つき）を出す" do
    result = run(columns: [ systolic, diastolic ], mappings: both)

    expect(result).to have_attributes(executed?: true, error: nil)
    expect(rows(result)).to eq([ [ "#{XV_BP}.v1", 150.0, 95.0 ], [ "#{XV_BP}.v1", 100.0, 60.0 ], [ "#{XV_BP}.v2", 120.0, 80.0 ] ])
  end

  it "条件は両方の版に効く: 収縮期 >= 120 は v1 の 150 と v2 の 120。「どちらかを満たす」（収縮期 >= 140 または拡張期 >= 80）も同じ 2 行" do
    expect(rows(run(columns: [ systolic ], conditions: [ { card: systolic, operator: ">=", value: "120" } ], mappings: both)))
      .to eq([ [ "#{XV_BP}.v1", 150.0 ], [ "#{XV_BP}.v2", 120.0 ] ])
    either = { any: [ { card: systolic, operator: ">=", value: "140" }, { card: diastolic, operator: ">=", value: "80" } ] }
    expect(rows(run(columns: [ systolic, diastolic ], conditions: [ either ], mappings: both)))
      .to eq([ [ "#{XV_BP}.v1", 150.0, 95.0 ], [ "#{XV_BP}.v2", 120.0, 80.0 ] ])
  end

  it "v1 のカードを選んでも、同じ結果になる" do
    result = run(columns: [ card("#{XV_BP}.v1", "at0004") ], mappings: both)

    expect(rows(result)).to eq([ [ "#{XV_BP}.v1", 150.0 ], [ "#{XV_BP}.v1", 100.0 ], [ "#{XV_BP}.v2", 120.0 ] ])
  end

  it "対応の無い項目を含む選択は組まない（ID が似ているだけの項目を、まとめて引かない）" do
    only_systolic = mappings("at0004")

    result = run(columns: [ systolic, diastolic ], mappings: only_systolic)
    expect(result).to have_attributes(executed?: false, aql: nil)
    expect(result.error).to eq("版の対応が無い項目がある: 拡張期（#{XV_BP}.v2 at0005）")

    other = run(columns: [ card(XV_PD, "at0002") ], mappings: both)
    expect(other.error).to eq("版の対応が無い項目がある: プロブレム・診断名（#{XV_PD} at0002）")
  end

  it "pending の対応（候補のまま）では組まない" do
    expect(run(columns: [ systolic ], mappings: mappings("at0004", status: "pending")).error).to include("版の対応が無い項目がある")
  end

  # R-20261125-11: リポジトリの表（config/version_mappings.yml）の血圧の 2 行が active になった
  it "リポジトリの表（既定）で、血圧の収縮期と拡張期を版をまたいで引ける" do
    result = run(columns: [ systolic, diastolic ])

    expect(result.error).to be_nil
    expect(rows(result)).to eq([ [ "#{XV_BP}.v1", 150.0, 95.0 ], [ "#{XV_BP}.v1", 100.0, 60.0 ], [ "#{XV_BP}.v2", 120.0, 80.0 ] ])
  end

  it "索引に片方の版のカードしか無ければ、その版だけを引く" do
    Template.active.find_by!(template_id: "patient_blood_pressure.v1").destroy!

    result = QueryBuilder::Runner.call(across_versions: true, columns: [ card("#{XV_BP}.v2", "at0004") ], mappings: both)

    expect(result.queries.map(&:archetype_id)).to eq([ "#{XV_BP}.v2" ])
    expect(rows(result)).to eq([ [ "#{XV_BP}.v2", 120.0 ] ])
  end

  it "どれかの版の AQL にリンタの error があれば、どの版も実行しない" do
    result = run(columns: [ systolic ], conditions: [ { card: systolic, operator: ">", value: "110" } ], mappings: both)
    expect(result.executed?).to be(true)

    allow(QueryBuilder::Linter).to receive(:lint).and_wrap_original do |original, aql, **options|
      lint = original.call(aql, **options)
      aql.include?(".v1]") ? QueryBuilder::Linter::Lint.new([ QueryBuilder::Finding.new(severity: :error, code: :path, message: "x", path: nil) ]) : lint
    end
    blocked = run(columns: [ systolic ], mappings: both)

    expect(blocked).to have_attributes(executed?: false, rows: [])
    expect(blocked.lint.ok?).to be(false)
  end

  it "across_versions を付けなければ、これまでどおり選んだ版だけを引く（先頭に版の列は無い）" do
    result = QueryBuilder::Runner.call(columns: [ systolic ], mappings: both)

    expect(rows(result)).to eq([ [ 120.0 ] ])
    expect(result.version_column?).to be(false)
    expect(result.queries.size).to eq(1)
  end
end
