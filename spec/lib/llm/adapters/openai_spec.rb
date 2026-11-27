require "rails_helper"
require "support/canned_http_server"

# OpenAI の Chat Completions の口のアダプタ（docs/design/s4-nl-aql-plan.md 11 節。R-20261127-25）。文を送って、文を受け取るだけ。
# gem を足さず、標準の Net::HTTP で呼ぶ。spec は、外を呼ばない: 開発機の中（127.0.0.1）に立てた、決まった応答を返すだけの
# サーバーを相手にする。鍵は、形だけの文字。口の形（URL、ヘッダ、本文と応答の項目）は、公式の文書で確かめた（ログ R5）。
RSpec.describe Llm::Adapters::Openai do
  KEY = "sk-not-a-real-key".freeze

  include CannedHttpServer

  # OpenAI の口は、接続先の下の /v1 に置く
  def serve(**options, &block) = super(path: "/v1", **options, &block)

  def adapter(base_url, **options)
    described_class.new(model: "the-model", api_key: KEY, base_url: base_url, **options)
  end

  def reply(content: %({"columns": [1]}), finish_reason: "stop", refusal: nil)
    JSON.generate(model: "the-model-2026", choices: [ { index: 0, finish_reason: finish_reason,
                                                       message: { role: "assistant", content: content, refusal: refusal } } ],
                  usage: { prompt_tokens: 1234, completion_tokens: 56, total_tokens: 1290 })
  end

  def failure(base_url, **options)
    adapter(base_url, **options).complete(instructions: "指示文", input: "問い")
    nil
  rescue Llm::Error => e
    e.message
  end

  describe "#complete" do
    it "POST <接続先>/chat/completions に、鍵（Bearer）、モデル、出力の上限、指示文（system）と入力（user）を送る" do
      serve(body: reply) do |base_url, requests|
        adapter(base_url).complete(instructions: "指示文", input: "候補の項目と問い")

        expect(requests.size).to eq(1)
        expect(requests.first[:line]).to eq("POST /v1/chat/completions HTTP/1.1")
        expect(requests.first[:header]).to match(/^authorization: Bearer #{KEY}\r?$/i)
        expect(requests.first[:header]).to match(%r{^content-type: application/json}i)
        expect(requests.first[:body]).to eq(
          "model" => "the-model", "max_completion_tokens" => described_class::MAX_TOKENS,
          "messages" => [ { "role" => "system", "content" => "指示文" }, { "role" => "user", "content" => "候補の項目と問い" } ]
        )
      end
    end

    it "応答の本文と、モデルの名前、トークンの数を返す" do
      serve(body: reply) do |base_url, _|
        response = adapter(base_url).complete(instructions: "指示文", input: "問い")

        expect(response.text).to eq(%({"columns": [1]}))
        expect(response.model).to eq("the-model-2026")
        expect(response.input_tokens).to eq(1234)
        expect(response.output_tokens).to eq(56)
      end
    end

    context "うまくいかないとき（どれも Llm::Error。理由に、鍵・応答の本文は入らない）" do
      it "断り（message.refusal がある、finish_reason が content_filter）" do
        serve(body: reply(content: nil, refusal: "断りの文")) { |url, _| expect(failure(url)).to eq("モデルが、応答を断りました。") }
        serve(body: reply(content: "", finish_reason: "content_filter")) { |url, _| expect(failure(url)).to eq("モデルが、応答を断りました。") }
      end

      it "出力の上限で、応答が途中で切れた（finish_reason が length）" do
        serve(body: reply(finish_reason: "length")) { |url, _| expect(failure(url)).to eq("応答が、出力の上限で途中で切れました。") }
      end

      it "本文が空、応答が JSON でない、決まった形でない" do
        serve(body: reply(content: nil)) { |url, _| expect(failure(url)).to eq("応答に、本文がありません。") }
        serve(body: "<html>") { |url, _| expect(failure(url)).to eq("API の応答が、読めませんでした。") }
        serve(body: %({"choices": "x"})) { |url, _| expect(failure(url)).to eq("API の応答が、読めませんでした。") }
      end

      it "鍵が受け付けられない（401）、回数の制限（429）、そのほかの状態。本文は出さない" do
        error = %({"error": {"message": "Incorrect API key provided: #{KEY}"}})
        serve(status: 401, body: error) do |url, _|
          expect(failure(url)).to eq("API の鍵が、受け付けられませんでした（401）。")
        end
        serve(status: 429, body: error) { |url, _| expect(failure(url)).to eq("API の回数の制限に当たりました（429）。") }
        serve(status: 503, body: error) { |url, _| expect(failure(url)).to eq("API が、エラーを返しました（503）。") }
      end

      it "時間切れ" do
        serve(body: reply, delay: 1) { |url, _| expect(failure(url, timeout: 0.2)).to eq("API の応答が、時間切れになりました。") }
      end

      it "つながらない（接続先に、だれもいない）" do
        expect(failure("http://127.0.0.1:#{closed_port}/v1")).to eq("API に、つながりませんでした。")
      end
    end
  end

  describe "名前と、外に送るかどうか" do
    it "名前は openai。接続先が OpenAI（既定）のとき、外に文を送る" do
      default = described_class.new(model: "the-model", api_key: KEY)

      expect(default.name).to eq("openai")
      expect(default).to be_external
    end

    it "接続先が開発機の中（127.0.0.1、localhost、::1）のときだけ、外に送らない扱い" do
      %w[http://127.0.0.1:11434/v1 http://localhost:11434/v1 http://[::1]:11434/v1].each do |url|
        expect(adapter(url)).not_to be_external
      end
      %w[https://api.openai.com/v1 https://example.com/v1 http://192.168.0.10:11434/v1 https://127.0.0.1.example.com/v1].each do |url|
        expect(adapter(url)).to be_external
      end
    end

    it "inspect に、鍵は出ない" do
      expect(adapter("https://api.openai.com/v1").inspect).not_to include(KEY)
    end
  end

  describe ".build（環境変数から作る。[アダプタ, nil] か [nil, 使えない理由]）" do
    it "鍵と、モデルの名前がそろうと、アダプタができる。接続先の既定は OpenAI" do
      adapter, reason = described_class.build("OPENAI_API_KEY" => KEY, "ANLAGE_LLM_MODEL" => "the-model")

      expect(adapter).to be_a(described_class)
      expect(adapter.base_url).to eq("https://api.openai.com/v1")
      expect(adapter).to be_external
      expect(reason).to be_nil
    end

    it "鍵が無い、モデルの名前が無いときは、使えない。理由が付く" do
      expect(described_class.build("ANLAGE_LLM_MODEL" => "the-model")).to eq([ nil, "API の鍵（OPENAI_API_KEY）がありません。" ])
      expect(described_class.build("OPENAI_API_KEY" => KEY)).to eq([ nil, "モデルの名前（ANLAGE_LLM_MODEL）がありません。" ])
    end

    it "Anthropic の鍵は、読まない" do
      expect(described_class.build("ANTHROPIC_API_KEY" => "sk-ant-not-a-real-key", "ANLAGE_LLM_MODEL" => "the-model").first).to be_nil
    end

    context "接続先を変える（ANLAGE_LLM_BASE_URL）" do
      it "開発機の中の接続先は、http でよく、鍵が無くてもよい" do
        adapter, reason = described_class.build("ANLAGE_LLM_MODEL" => "the-model", "ANLAGE_LLM_BASE_URL" => "http://127.0.0.1:11434/v1")

        expect(reason).to be_nil
        expect(adapter).not_to be_external
      end

      it "開発機の外の接続先は、https だけ（鍵と問いの文を、平文で送らない）。鍵も要る" do
        env = { "OPENAI_API_KEY" => KEY, "ANLAGE_LLM_MODEL" => "the-model" }

        expect(described_class.build(env.merge("ANLAGE_LLM_BASE_URL" => "http://example.com/v1")))
          .to eq([ nil, "接続先（ANLAGE_LLM_BASE_URL）が、開発機の外なのに https ではありません。" ])
        expect(described_class.build("ANLAGE_LLM_MODEL" => "the-model", "ANLAGE_LLM_BASE_URL" => "https://example.com/v1"))
          .to eq([ nil, "API の鍵（OPENAI_API_KEY）がありません。" ])
        expect(described_class.build(env.merge("ANLAGE_LLM_BASE_URL" => "https://example.com/v1")).first).to be_external
      end

      it "URL として読めない接続先は、使えない" do
        expect(described_class.build("OPENAI_API_KEY" => KEY, "ANLAGE_LLM_MODEL" => "the-model", "ANLAGE_LLM_BASE_URL" => "ここ"))
          .to eq([ nil, "接続先（ANLAGE_LLM_BASE_URL）が、URL として読めません。" ])
      end
    end
  end
end
