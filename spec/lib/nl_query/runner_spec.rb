require "rails_helper"

# 問い合わせの流れ（docs/design/s4-nl-aql-plan.md 1 節）: 問い → 候補のカード → アダプタ → 選択 → AQL → リンタ →（実行）→ 説明。
# LLM の応答は、記録した応答（Llm::Adapters::Recorded）で固定する。記録の鍵は送った文の sha256 なので、
# spec は、同じ候補から組んだ文の sha256 で記録を書く。ここの応答は、セッションが手で書いたもの（モデルの応答ではない）。
# うまくいかないときは、どれも例外にせず、候補のカードだけを返す（クエリビルダーに落ちる）。
RSpec.describe NlQuery::Runner do
  QUESTION = "診断確度が「疑い」の傷病名".freeze

  let(:recordings) { Pathname(Dir.mktmpdir) }
  let(:usage_dir) { Pathname(Dir.mktmpdir) }
  let(:usage) { Llm::Usage.new(path: usage_dir.join("llm_usage.json"), clock: -> { Date.new(2026, 11, 27) }) }
  let(:settings) { Llm::Settings.from_env("ANLAGE_LLM" => "recorded", "ANLAGE_LLM_RECORDINGS" => recordings.to_s) }
  let(:corpus) { QueryBuilder::Corpus.active }
  let(:candidates) { NlQuery::Candidates.call(QUESTION, corpus: corpus) }

  before { Evaluation::Datasets.build("demo_initial") }

  after do
    FileUtils.remove_entry(recordings)
    FileUtils.remove_entry(usage_dir)
  end

  # 候補の中の番号（1 から）。テンプレートと項目名で引く
  def number(template_id, label)
    candidates.index { |card| card.dig("identity", "template_id") == template_id && card.dig("semantics", "labels", 0, "text") == label } + 1
  end

  def record(response, question: QUESTION)
    prompt = NlQuery::Prompt.new(question: question, cards: NlQuery::Candidates.call(question, corpus: corpus))
    text = response.is_a?(String) ? response : JSON.generate(response)
    recordings.join("#{prompt.sha256}.json").write(JSON.generate(
      sha256: prompt.sha256, input: prompt.input, response: text, model: "hand-written", input_tokens: 900, output_tokens: 40, source: "hand_written"
    ))
  end

  def run(question = QUESTION, **options)
    described_class.call(question: question, settings: settings, usage: usage, corpus: corpus, **options)
  end

  let(:a002_response) do
    { columns: [ number("ProblemList", "プロブレム・診断名") ],
      conditions: [ { card: number("ProblemList", "診断確度"), operator: "MATCHES", value: [ "疑い" ] } ] }
  end

  describe "つながる（a002。記録した応答で）" do
    before { record(a002_response) }

    it "問いから、選択と AQL と説明ができる。AQL は参照 AQL と同じ形で、リンタを通る" do
      result = run

      expect(result).to be_ok
      expect(result.run.aql).to eq(<<~AQL.chomp)
        SELECT ev/data[at0001]/items[at0002]/value/value
        FROM EHR e CONTAINS COMPOSITION c CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
        WHERE ev/data[at0001]/items[at0073]/value/defining_code/code_string MATCHES {"at0074"}
      AQL
      expect(result.run.lint).to be_ok
      expect(result.explanation).to eq(
        "「プロブレム・診断」の「プロブレム・診断名」を表示します。条件: 「診断確度」が 疑い（at0074）。" \
        "アーキタイプ: openEHR-EHR-EVALUATION.problem_diagnosis.v1。テンプレート: ProblemList。"
      )
      expect(result.candidates).to eq(candidates)
      expect(result.sha256).to match(/\A\h{64}\z/)
      expect(result.model).to eq("hand-written")
    end

    it "既定では実行しない（選択を画面に入れて、利用者が見てから実行する）" do
      expect(run.run).not_to be_executed
    end

    it "execute: true で実行すると、a002 の期待行が返る" do
      result = run(execute: true)

      expect(result.run).to be_executed
      expect(result.run.rows.flatten).to match_array(%w[高血圧症 起立性低血圧 狭心症 狭心症 白血病 悪性リンパ腫 多発性骨髄腫])
    end

    it "呼んだ回数と、トークンの数を数える" do
      run

      expect(usage.today).to eq(calls: 1, input_tokens: 900, output_tokens: 40)
    end
  end

  describe "候補のカードだけを返す（クエリビルダーに落ちる。例外にしない）" do
    it "オフのとき。アダプタを呼ばない" do
      result = described_class.call(question: QUESTION, settings: Llm::Settings.from_env({}), usage: usage, corpus: corpus)

      expect(result.status).to eq(:off)
      expect(result).not_to be_ok
      expect(result.selection).to be_nil
      expect(result.run).to be_nil
      expect(result.candidates).to eq(candidates)
      expect(usage.today[:calls]).to eq(0)
    end

    it "回数の上限に達しているとき。アダプタを呼ばない。理由が付く" do
      record(a002_response)
      limited = Llm::Settings.from_env("ANLAGE_LLM" => "recorded", "ANLAGE_LLM_RECORDINGS" => recordings.to_s,
                                       "ANLAGE_LLM_DAILY_CALL_LIMIT" => "1")
      first = described_class.call(question: QUESTION, settings: limited, usage: usage, corpus: corpus)
      second = described_class.call(question: QUESTION, settings: limited, usage: usage, corpus: corpus)

      expect(first).to be_ok
      expect(second.status).to eq(:limit)
      expect(second.reason).to eq("きょうの呼び出しの回数が、上限（1 回）に達しました。")
      expect(second.candidates).to eq(candidates)
      expect(usage.today[:calls]).to eq(1)
    end

    it "応答が読めないとき。理由が付く" do
      record("プロブレム・診断名を表示します。")

      result = run
      expect(result.status).to eq(:rejected)
      expect(result.reason).to include("JSON として読めない")
      expect(result.candidates).to eq(candidates)
      expect(result.selection).to be_nil
    end

    it "LLM が「答えられない」と返したとき。理由をそのまま返す" do
      record({ columns: [], conditions: [], reason: "候補の項目に、体重がありません。" })

      result = run
      expect(result.status).to eq(:unanswerable)
      expect(result.reason).to eq("候補の項目に、体重がありません。")
    end

    it "クエリビルダーが組めない選択（2 つのアーキタイプにまたがる）のとき。実行しない" do
      record({ columns: [ number("ProblemList", "プロブレム・診断名"), number("CardiologyEncounter", "収縮期") ], conditions: [] })

      result = run(execute: true)
      expect(result.status).to eq(:rejected)
      expect(result.reason).to include("1 つのクエリで使える ENTRY のアーキタイプは 1 つ")
      expect(result.run).to be_nil
    end

    it "リンタの error がある AQL は、実行しない" do
      record(a002_response)
      error = QueryBuilder::Finding.new(severity: :error, code: :spec, message: "spec が差し込んだ error")
      allow(QueryBuilder::Linter).to receive(:lint).and_return(QueryBuilder::Linter::Lint.new([ error ]))
      expect(OpenehrRails::Aql::Executor).not_to receive(:execute)

      result = run(execute: true)
      expect(result.status).to eq(:rejected)
      expect(result.reason).to include("spec が差し込んだ error")
    end

    it "アダプタが落ちたとき（記録が無い、通信の失敗、時間切れ）。回数は数える" do
      result = run

      expect(result.status).to eq(:failed)
      expect(result.reason).to include("記録が無い")
      expect(result.candidates).to eq(candidates)
      expect(usage.today[:calls]).to eq(1)
    end

    it "アダプタが、Llm::Error でない例外で落ちたときも、画面を落とさない。例外の文は出さない" do
      broken = Class.new do
        def name = "broken"
        def external? = false
        def complete(instructions:, input:) = raise(IOError, "sk-ant-secret を含むかもしれない文")
      end.new

      result = described_class.call(question: QUESTION, settings: Llm::Settings.new(adapter: broken, adapter_name: "broken"),
                                    usage: usage, corpus: corpus)
      expect(result.status).to eq(:failed)
      expect(result.reason).to eq("LLM の呼び出しに失敗しました（IOError）。")
    end

    it "問いが空のとき。アダプタを呼ばない" do
      result = run("  ")

      expect(result.status).to eq(:blank)
      expect(usage.today[:calls]).to eq(0)
    end
  end
end
