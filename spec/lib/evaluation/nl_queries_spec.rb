require "rails_helper"

# 測定に使う問いの文（spec/fixtures/evaluation/nl/nl_queries.yml。裁定 R-20261127-26 で確定）の、形と、正解の行の実測を固定する。
# 正解の行は、demo_initial（rake demo:reset の初期状態）で、クエリビルダーが組んだ AQL を実行した結果と同じであること。
# ここは読み込みと照合だけ。問いの文と正解の行そのものは、人間の専有領域。
RSpec.describe "測定に使う問いの文（nl_queries.yml）" do
  data = YAML.load_file(Rails.root.join("spec/fixtures/evaluation/nl/nl_queries.yml"), permitted_classes: [ Date ], aliases: true)
  queries = data.fetch("queries")

  let(:gold) { Evaluation::Questions.from_v2.select(&:aql?).index_by(&:id) }
  let(:corpus) { QueryBuilder::Corpus.active }

  def rows_of(selection, across_versions: false)
    question = Evaluation::Question.new(id: "x", kind: :aql, query: "x", selection: selection)
    route = Evaluation::BuilderRoute.new(question, corpus)
    columns = selection[:columns].map { |ref| route.send(:card, ref) }
    conditions = selection[:conditions].map { |condition| route.send(:resolve, condition) }
    run = QueryBuilder::Runner.call(columns: columns, conditions: conditions, across_versions: across_versions, corpus: corpus)
    raise "実行できない: #{run.error || run.lint.findings.map(&:message).join('／')}" unless run.executed?

    run.rows
  end

  def symbolize(selection)
    { columns: selection["columns"].map { |ref| ref.transform_keys(&:to_sym) },
      conditions: selection["conditions"].map { |c| { card: c["card"].transform_keys(&:to_sym), operator: c["operator"], value: c["value"] } } }
  end

  it "レビューの記録がある。draft は残っていない" do
    expect(data["reviewed_by"]).to eq("Kobayashi, Shinji")
    expect(data["reviewed_at"]).to eq(Date.new(2026, 11, 27))
    expect(queries.map { |query| query["status"] }.compact).to be_empty
  end

  it "id は重ならない。style と tags は、決めた語だけ" do
    expect(queries.map { |query| query["id"] }).to eq(queries.map { |query| query["id"] }.uniq)
    expect(queries.map { |query| query["style"] }.uniq).to match_array(%w[base chart explain modeling tuning])
    expect(queries.flat_map { |query| Array(query["tags"]) }.uniq).to match_array(%w[abbrev value_paraphrase named_template])
  end

  it "測定に使う文は 37、調整用は 3。「帳票」は残っていない" do
    measured = queries.reject { |query| query["style"] == "tuning" }

    expect(measured.size).to eq(37)
    expect(queries.size - measured.size).to eq(3)
    expect(measured.group_by { |query| query["style"] }.transform_values(&:size)).to eq("base" => 16, "chart" => 12, "explain" => 7, "modeling" => 2)
    expect(queries.map { |query| query["nl_query"] }.grep(/帳票/)).to be_empty
  end

  it "base は、評価 v2 の aql の問いを指す。正解の行を、どれかの決まりで引ける" do
    queries.reject { |query| query["style"] == "tuning" }.each do |query|
      expect(gold).to have_key(query["base"]) if query["base"]
      expect(query["expected_rows"] || data["both_versions"][query["base"]] || gold[query["base"]]&.expected_rows).to be_present, query["id"]
    end
  end

  context "demo_initial での実測" do
    before { Evaluation::Datasets.build("demo_initial") }

    it "テンプレートを名指ししない血圧の問い: v1 と v2 の両方を引いた行が、rows_by_archetype と同じ" do
      expect(data["both_versions"].keys).to eq(%w[a001 a009 a010 a011])
      data["both_versions"].each do |base, expected|
        selection = gold.fetch(base).selection
        by_archetype = rows_of(selection, across_versions: true).group_by(&:first).transform_values { |rows| rows.map { |row| row.drop(1) } }

        expected["rows_by_archetype"].each do |archetype_id, rows|
          expect(by_archetype.fetch(archetype_id, [])).to match_array(rows), "#{base} #{archetype_id}"
        end
        expect(by_archetype.keys - expected["rows_by_archetype"].keys).to be_empty
      end
    end

    it "expected_rows を持つ問い（名指しの文、検査の 2 問）: selection から組んだ AQL の行と同じ" do
      own = queries.select { |query| query["expected_rows"] }

      expect(own.map { |query| query["id"] }).to eq(%w[n001-4 n001-5 n101-1 n101-2 n102-1 n102-2])
      own.each { |query| expect(rows_of(symbolize(query["selection"]))).to match_array(query["expected_rows"]), query["id"] }
    end
  end
end
