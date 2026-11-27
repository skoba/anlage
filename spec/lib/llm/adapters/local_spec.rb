require "rails_helper"
require "support/canned_http_server"

# 手元で動くモデルのアダプタ（docs/design/s4-nl-aql-plan.md 14 節。R-20261127-29）。Ollama の元の口（POST /api/chat）。
# 考える分を止め（think: false）、出力の形を渡されたら縛る（format に JSON スキーマ）。接続先は、開発機の中だけ。外に送らない。
# spec は、開発機の中に立てた、決まった応答を返すサーバーを相手にする。手元のモデルは呼ばない。
# 口の形は、公式の文書と、開発機での試し（docs/reports/s4-local-model-candidates.md）で確かめた。
RSpec.describe Llm::Adapters::Local do
  include CannedHttpServer

  SCHEMA = { type: "object", required: %w[columns], properties: { columns: { type: "array", items: { type: "integer" } } } }.freeze

  def adapter(base_url, **options)
    described_class.new(model: "qwen3:4b", base_url: base_url, **options)
  end

  def reply(content: %({"columns": [1]}), done_reason: "stop")
    JSON.generate(model: "qwen3:4b", message: { role: "assistant", content: content }, done: true, done_reason: done_reason,
                  prompt_eval_count: 2473, eval_count: 68)
  end

  def failure(base_url, **options)
    adapter(base_url, **options).complete(instructions: "指示文", input: "問い")
    nil
  rescue Llm::Error => e
    e.message
  end

  describe "#complete" do
    it "POST <接続先>/api/chat に、モデル、指示文（system）と入力（user）を送る。考える分を止め、まとめて受け取る" do
      serve(body: reply) do |base_url, requests|
        adapter(base_url).complete(instructions: "指示文", input: "候補の項目と問い")

        expect(requests.first[:line]).to eq("POST /api/chat HTTP/1.1")
        expect(requests.first[:header]).not_to match(/^authorization:/i)
        expect(requests.first[:body]).to eq(
          "model" => "qwen3:4b", "stream" => false, "think" => false, "options" => { "num_predict" => described_class::MAX_TOKENS },
          "messages" => [ { "role" => "system", "content" => "指示文" }, { "role" => "user", "content" => "候補の項目と問い" } ]
        )
      end
    end

    it "出力の形（JSON スキーマ）を渡されたら、format に入れる" do
      serve(body: reply) do |base_url, requests|
        adapter(base_url).complete(instructions: "指示文", input: "問い", json_schema: SCHEMA)

        expect(requests.first[:body]["format"]).to eq(JSON.parse(JSON.generate(SCHEMA)))
      end
    end

    it "温度と乱数の種は、指定したときだけ送る（測定の設定に書くため）" do
      serve(body: reply) do |base_url, requests|
        adapter(base_url, temperature: 0, seed: 42).complete(instructions: "指示文", input: "問い")

        expect(requests.first[:body]["options"]).to eq("num_predict" => described_class::MAX_TOKENS, "temperature" => 0, "seed" => 42)
      end
    end

    it "応答の本文と、モデルの名前、トークンの数を返す" do
      serve(body: reply) do |base_url, _|
        response = adapter(base_url).complete(instructions: "指示文", input: "問い")

        expect(response.text).to eq(%({"columns": [1]}))
        expect(response.model).to eq("qwen3:4b")
        expect(response.input_tokens).to eq(2473)
        expect(response.output_tokens).to eq(68)
      end
    end

    context "うまくいかないとき（どれも Llm::Error）" do
      it "出力の上限で途中で切れた（done_reason が length）、本文が空、読めない応答" do
        serve(body: reply(done_reason: "length")) { |url, _| expect(failure(url)).to eq("応答が、出力の上限で途中で切れました。") }
        serve(body: reply(content: " ")) { |url, _| expect(failure(url)).to eq("応答に、本文がありません。") }
        serve(body: "<html>") { |url, _| expect(failure(url)).to eq("手元のモデルの応答が、読めませんでした。") }
      end

      it "モデルが入っていない（404）、そのほかの状態。本文は出さない" do
        serve(status: 404, body: %({"error": "model 'x' not found"})) do |url, _|
          expect(failure(url)).to eq("手元のモデルが、見つかりませんでした（404）。モデルの名前と、入れてあるかを確かめてください。")
        end
        serve(status: 500, body: %({"error": "x"})) { |url, _| expect(failure(url)).to eq("手元のモデルが、エラーを返しました（500）。") }
      end

      it "時間切れ、つながらない" do
        serve(body: reply, delay: 1) { |url, _| expect(failure(url, timeout: 0.2)).to eq("手元のモデルの応答が、時間切れになりました。") }
        expect(failure("http://127.0.0.1:#{closed_port}")).to eq("手元のモデルに、つながりませんでした。")
      end
    end
  end

  it "名前は local。外に文を送らない" do
    expect(adapter("http://127.0.0.1:11434").name).to eq("local")
    expect(adapter("http://127.0.0.1:11434")).not_to be_external
  end

  describe ".build（環境変数から作る。[アダプタ, nil] か [nil, 使えない理由]）" do
    it "モデルの名前があれば、できる。接続先の既定は、開発機の中の Ollama の口。鍵は要らない" do
      adapter, reason = described_class.build("ANLAGE_LLM_MODEL" => "qwen3:4b")

      expect(reason).to be_nil
      expect(adapter.base_url).to eq("http://127.0.0.1:11434")
      expect(adapter.model).to eq("qwen3:4b")
    end

    it "モデルの名前が無いときは、使えない" do
      expect(described_class.build({})).to eq([ nil, "モデルの名前（ANLAGE_LLM_MODEL）がありません。" ])
    end

    it "接続先は、開発機の中（127.0.0.1、localhost、::1）だけ。外の接続先は、https でも使えない" do
      expect(described_class.build("ANLAGE_LLM_MODEL" => "qwen3:4b", "ANLAGE_LLM_BASE_URL" => "http://localhost:11434").last).to be_nil
      %w[https://example.com http://192.168.0.10:11434].each do |url|
        expect(described_class.build("ANLAGE_LLM_MODEL" => "qwen3:4b", "ANLAGE_LLM_BASE_URL" => url))
          .to eq([ nil, "local の接続先（ANLAGE_LLM_BASE_URL）は、開発機の中（127.0.0.1、localhost）だけです。" ])
      end
      expect(described_class.build("ANLAGE_LLM_MODEL" => "qwen3:4b", "ANLAGE_LLM_BASE_URL" => "ここ"))
        .to eq([ nil, "接続先（ANLAGE_LLM_BASE_URL）が、URL として読めません。" ])
    end
  end
end
