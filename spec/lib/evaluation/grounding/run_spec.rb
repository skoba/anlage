require "rails_helper"

# 測定を回す（問い × 腕 × くり返し）。試行ごとに、記録のファイルを 1 つ残す。途中で止めても、済んだ分は残り、続きから回せる。
# 記録から、アダプタを呼ばずに、同じ集計を作り直せる（計画書 5.5 節・7 節の段 6。R-20261127-32）。
# ここのアダプタは、spec の中の偽物（決まった応答を返す）。外も、手元のモデルも呼ばない。
RSpec.describe Evaluation::Grounding::Run do
  before { Evaluation::Datasets.build("demo_initial") }

  let(:dir) { Pathname(Dir.mktmpdir) }
  let(:corpus) { QueryBuilder::Corpus.active }
  let(:queries) { Evaluation::Grounding::Queries.load.select { |query| %w[n001-1 n001-4 n014-1].include?(query.id) } }
  let(:calls) { [] }
  let(:adapter) do
    log = calls
    aql = "SELECT o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude FROM EHR e CONTAINS COMPOSITION c " \
          "CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2] WHERE o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude >= 140"
    Class.new do
      define_method(:name) { "fake" }
      define_method(:external?) { false }
      define_method(:complete) do |instructions:, input:, json_schema: nil|
        log << { instructions: instructions, input: input, json_schema: json_schema }
        raise Llm::Error, "落ちた" if input.include?("落とす")

        Llm::Response.new(text: JSON.generate(aqls: [ aql ]), model: "fake-1", input_tokens: 100, output_tokens: 20)
      end
    end.new
  end

  after { FileUtils.remove_entry(dir) }

  def run(**options)
    Evaluation::Grounding::Run.call(queries: queries, arms: %i[n1 g_aql], adapter: adapter, repeats: 2, dir: dir, corpus: corpus, **options)
  end

  it "問い × 腕 × くり返しを回し、試行ごとに記録を残す。選択を出す腕だけで数える問いは、AQL の腕では回さない" do
    run

    files = dir.glob("trials/*.json").map { |path| path.basename.to_s }.sort
    expect(files).to eq(%w[n001-1.g_aql.1.json n001-1.g_aql.2.json n001-1.n1.1.json n001-1.n1.2.json
                           n001-4.g_aql.1.json n001-4.g_aql.2.json n001-4.n1.1.json n001-4.n1.2.json])
    expect(calls.size).to eq(8)
  end

  it "試行の記録に、送った文、返ってきた文、採点、時間、トークンの数、モデルの名前、送った文の sha256 が入る" do
    run
    trial = JSON.parse(dir.join("trials/n001-4.g_aql.1.json").read)

    expect(trial).to include("query" => "n001-4", "arm" => "g_aql", "repeat" => 1, "status" => "match", "order_free" => true,
                             "parseable" => true, "lint_ok" => true, "executed" => true, "model" => "fake-1",
                             "input_tokens" => 100, "output_tokens" => 20)
    expect(trial["instructions_sha256"]).to match(/\A\h{64}\z/)
    expect(trial["input"]).to include("問い: ")
    expect(trial["response"]).to include("aqls")
    expect(trial["seconds"]).to be_a(Numeric)
    expect(JSON.parse(dir.join("trials/n001-1.n1.1.json").read)["status"]).to eq("overlooked")
  end

  it "測定の記録（run.json）に、アダプタ、腕、回数、問いのファイルの sha256、commit、gem の版、出力の形を縛ったかが入る。鍵は入らない" do
    run(note: "spec")
    meta = JSON.parse(dir.join("run.json").read)

    expect(meta).to include("adapter" => "fake", "arms" => %w[n1 g_aql], "repeats" => 2, "queries_sha256" => Evaluation::Grounding::Queries.sha256,
                            "json_schema" => { "n1" => false, "g_aql" => false }, "note" => "spec")
    expect(meta["commit"]).to match(/\A\h{7,40}\z/)
    expect(meta["gems"].keys).to include("openehr", "openehr-rails")
    expect(meta["started_at"]).to be_present
    expect(dir.glob("**/*.json").map(&:read).join).not_to match(/sk-|api_key|Authorization/i)
  end

  it "途中で止めても、済んだ分は残る。もう一度回すと、済んだ試行は呼ばずに、続きだけ回す" do
    run
    dir.join("trials/n001-4.n1.2.json").delete
    calls.clear

    run
    expect(calls.size).to eq(1)
    expect(dir.glob("trials/*.json").size).to eq(8)
  end

  it "アダプタが落ちた試行は、failed として記録し、次に進む（回数に数える）" do
    failing = Evaluation::Grounding::Queries::Query.new(id: "x001", base: nil, style: "base", tags: [], nl_query: "落とす", expected_rows: [ [ 1.0 ] ], cards: [])
    described_class.call(queries: [ failing ], arms: %i[n0], adapter: adapter, repeats: 1, dir: dir, corpus: corpus)

    expect(JSON.parse(dir.join("trials/x001.n0.1.json").read)).to include("status" => "failed", "reason" => "落ちた")
  end

  it "選択を出す腕には、選択の形（JSON スキーマ）を渡す。AQL の腕には渡さない" do
    described_class.call(queries: queries.first(1), arms: %i[g_selection n0], adapter: adapter, repeats: 1, dir: dir, corpus: corpus)

    expect(calls.map { |call| call[:json_schema].present? }).to eq([ true, false ])
    expect(JSON.parse(dir.join("run.json").read)["json_schema"]).to eq("g_selection" => true, "n0" => false)
  end

  describe Evaluation::Grounding::Report do
    it "記録から、アダプタを呼ばずに、集計を作る: 腕ごとの、正解・見落とし・不正解と、列の順を見ない一致" do
      run
      calls.clear
      report = described_class.render(dir)

      expect(calls).to be_empty
      expect(report).to include("| n1 | 4 | 2 | 2 | 0 | 0 | 0 | 0 | 0 | 2 |")
      expect(report).to include("| g_aql | 4 | 2 | 2 | 0 | 0 | 0 | 0 | 0 | 2 |")
      expect(report).to include("| n001-1 | n1 | 0/2 | 2/2 |")
      expect(report).to include("| n001-4 | g_aql | 2/2 | 0/2 |")
    end

    it "限界を書く: 問いの数、モデルの出どころ、接地ありの腕がカードをすべて渡していること" do
      run
      report = described_class.render(dir)

      expect(report).to include("「接地あり」の腕は、索引のカードをすべて渡している")
      expect(report).to include("問いは、このアプリのカードから作った")
    end
  end
end
