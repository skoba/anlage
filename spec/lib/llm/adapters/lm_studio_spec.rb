require "rails_helper"
require "support/canned_http_server"

# LM Studio（同じ機械の中）の手元のモデルのアダプタ（docs/design/s4-nl-aql-plan.md 15 節。R-20261128-5）。
# OpenAI と同じ形の口（POST <接続先>/chat/completions）。出力の形を渡されたら、response_format（json_schema）で縛る。
# 接続先は、開発機の中だけ。外に送らない。spec は、開発機の中に立てた、決まった応答を返すサーバーを相手にする。LM Studio は呼ばない。
# 口の形は、LM Studio の公式の文書で確かめた（計画書 15.2 節。2026-11-28）。
RSpec.describe Llm::Adapters::LmStudio do
  include CannedHttpServer

  # LM Studio の、OpenAI と同じ形の口は、接続先の下の /v1 に置く
  def serve(**options, &block) = super(path: "/v1", **options, &block)

  def schema = { type: "object", required: %w[columns], properties: { columns: { type: "array", items: { type: "integer" } } } }
  def token = "lm-not-a-real-token"

  def adapter(base_url, **options)
    described_class.new(model: "google/gemma-4-12b", base_url: base_url, **options)
  end

  def reply(content: %({"columns": [1]}), finish_reason: "stop", **message)
    JSON.generate(model: "google/gemma-4-12b", choices: [ { index: 0, finish_reason: finish_reason,
                                                           message: { role: "assistant", content: content, **message } } ],
                  usage: { prompt_tokens: 1500, completion_tokens: 70, total_tokens: 1570 })
  end

  def failure(base_url, **options)
    adapter(base_url, **options).complete(instructions: "指示文", input: "問い")
    nil
  rescue Llm::Error => e
    e.message
  end

  describe "#complete" do
    it "POST <接続先>/chat/completions に、モデル、出力の上限（max_tokens）、指示文（system）と入力（user）を送る。まとめて受け取る" do
      serve(body: reply) do |base_url, requests|
        adapter(base_url).complete(instructions: "指示文", input: "候補の項目と問い")

        expect(requests.first[:line]).to eq("POST /v1/chat/completions HTTP/1.1")
        expect(requests.first[:header]).not_to match(/^authorization:/i)
        expect(requests.first[:body]).to eq(
          "model" => "google/gemma-4-12b", "stream" => false, "max_tokens" => described_class::MAX_TOKENS,
          "messages" => [ { "role" => "system", "content" => "指示文" }, { "role" => "user", "content" => "候補の項目と問い" } ]
        )
      end
    end

    it "出力の形（JSON スキーマ）を渡されたら、response_format（json_schema）に入れる" do
      serve(body: reply) do |base_url, requests|
        adapter(base_url).complete(instructions: "指示文", input: "問い", json_schema: schema)

        expect(requests.first[:body]["response_format"]).to eq(
          "type" => "json_schema", "json_schema" => { "name" => "output", "schema" => JSON.parse(JSON.generate(schema)) }
        )
      end
    end

    it "API のトークンがあるときだけ、Authorization: Bearer で送る（LM Studio が、トークンを求める設定のとき）" do
      serve(body: reply) do |base_url, requests|
        adapter(base_url, api_token: token).complete(instructions: "指示文", input: "問い")

        expect(requests.first[:header]).to match(/^authorization: Bearer #{token}\r?$/i)
      end
    end

    it "温度と乱数の種は、指定したときだけ送る（測定の設定に書くため）" do
      serve(body: reply) do |base_url, requests|
        adapter(base_url, temperature: 0, seed: 42).complete(instructions: "指示文", input: "問い")

        expect(requests.first[:body]).to include("temperature" => 0, "seed" => 42)
      end
    end

    it "応答の本文と、モデルの名前、トークンの数を返す" do
      serve(body: reply) do |base_url, _|
        response = adapter(base_url).complete(instructions: "指示文", input: "問い")

        expect(response.text).to eq(%({"columns": [1]}))
        expect(response.model).to eq("google/gemma-4-12b")
        expect(response.input_tokens).to eq(1500)
        expect(response.output_tokens).to eq(70)
      end
    end

    it "応答に usage が無くても、本文は返す（トークンの数は nil）" do
      body = JSON.generate(model: "m", choices: [ { finish_reason: "stop", message: { role: "assistant", content: "{}" } } ])
      serve(body: body) do |base_url, _|
        response = adapter(base_url).complete(instructions: "指示文", input: "問い")

        expect([ response.text, response.input_tokens, response.output_tokens ]).to eq([ "{}", nil, nil ])
      end
    end

    context "うまくいかないとき（どれも Llm::Error。理由に、トークン・応答の本文は入らない）" do
      it "出力の上限で途中で切れた（finish_reason が length）、本文が空、読めない応答" do
        serve(body: reply(finish_reason: "length")) { |url, _| expect(failure(url)).to eq("応答が、出力の上限で途中で切れました。") }
        serve(body: reply(content: " ")) { |url, _| expect(failure(url)).to eq("応答に、本文がありません。") }
        serve(body: "<html>") { |url, _| expect(failure(url)).to eq("LM Studio の応答が、読めませんでした。") }
      end

      it "考える分だけが返って、本文が空（message.reasoning か reasoning_content がある）" do
        %i[reasoning reasoning_content].each do |field|
          serve(body: reply(content: "", field => "考えた文")) do |url, _|
            expect(failure(url)).to eq("考える分だけが返り、本文がありません。")
          end
        end
      end

      it "トークンが受け付けられない（401）、そのほかの状態。本文は出さない" do
        serve(status: 401, body: %({"error": "x"})) do |url, _|
          expect(failure(url, api_token: token)).to eq("LM Studio が、API のトークンを受け付けませんでした（401）。LM_API_TOKEN を確かめてください。")
        end
        serve(status: 500, body: %({"error": "秘密の文"})) { |url, _| expect(failure(url)).to eq("LM Studio が、エラーを返しました（500）。") }
      end

      it "時間切れ、つながらない" do
        serve(body: reply, delay: 1) { |url, _| expect(failure(url, timeout: 0.2)).to eq("LM Studio の応答が、時間切れになりました。") }
        expect(failure("http://127.0.0.1:#{closed_port}/v1")).to eq("LM Studio に、つながりませんでした。サーバーが立っているかを確かめてください。")
      end
    end
  end

  it "名前は lmstudio。外に文を送らない。inspect に、トークンを出さない" do
    built = adapter("http://127.0.0.1:1234/v1", api_token: token)

    expect(built.name).to eq("lmstudio")
    expect(built).not_to be_external
    expect(built.inspect).not_to include(token)
  end

  describe ".build（環境変数から作る。[アダプタ, nil] か [nil, 使えない理由]）" do
    it "モデルの名前があれば、できる。接続先の既定は、開発機の中の LM Studio の口。トークンは要らない" do
      adapter, reason = described_class.build("ANLAGE_LLM_MODEL" => "google/gemma-4-12b")

      expect(reason).to be_nil
      expect(adapter.base_url).to eq("http://127.0.0.1:1234/v1")
      expect(adapter.model).to eq("google/gemma-4-12b")
    end

    it "トークン（LM_API_TOKEN）があれば、送る。温度と乱数の種は、作るときに足せる" do
      serve(body: reply) do |base_url, requests|
        adapter, = described_class.build({ "ANLAGE_LLM_MODEL" => "m", "ANLAGE_LLM_BASE_URL" => base_url, "LM_API_TOKEN" => token }, seed: 1)
        adapter.complete(instructions: "指示文", input: "問い")

        expect(requests.first[:header]).to match(/^authorization: Bearer #{token}\r?$/i)
        expect(requests.first[:body]["seed"]).to eq(1)
      end
    end

    it "モデルの名前が無いときは、使えない" do
      expect(described_class.build({})).to eq([ nil, "モデルの名前（ANLAGE_LLM_MODEL）がありません。" ])
    end

    it "接続先は、開発機の中（127.0.0.1、localhost、::1）だけ。外の接続先は、https でも使えない" do
      expect(described_class.build("ANLAGE_LLM_MODEL" => "m", "ANLAGE_LLM_BASE_URL" => "http://localhost:1234/v1").last).to be_nil
      %w[https://example.com/v1 http://192.168.0.10:1234/v1].each do |url|
        expect(described_class.build("ANLAGE_LLM_MODEL" => "m", "ANLAGE_LLM_BASE_URL" => url))
          .to eq([ nil, "lmstudio の接続先（ANLAGE_LLM_BASE_URL）は、開発機の中（127.0.0.1、localhost）だけです。" ])
      end
      expect(described_class.build("ANLAGE_LLM_MODEL" => "m", "ANLAGE_LLM_BASE_URL" => "ここ"))
        .to eq([ nil, "接続先（ANLAGE_LLM_BASE_URL）が、URL として読めません。" ])
    end
  end
end
