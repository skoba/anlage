require "rails_helper"
require "anthropic"

# Claude API のアダプタ（docs/design/s4-nl-aql-plan.md 7 節の段 4）。文を送って、文を受け取るだけ。
# spec は、SDK のクライアントと同じ口（messages.create）を持つ偽物を差し込む。外を呼ばない。鍵は使わない。
# SDK の呼び方（引数の名前、応答の形、例外のクラス）は、gem anthropic 2.14.0 のソースで確かめた（docs/reports/s4-nl-query-log.md R4）。
RSpec.describe Llm::Adapters::Anthropic do
  # Anthropic::Models::Message の、使う項目だけを持つ偽物
  FakeMessage = Struct.new(:content, :model, :stop_reason, :usage, keyword_init: true)
  FakeBlock = Struct.new(:type, :text, keyword_init: true)
  FakeUsage = Struct.new(:input_tokens, :output_tokens, keyword_init: true)

  let(:calls) { [] }
  let(:reply) do
    FakeMessage.new(content: [ FakeBlock.new(type: :thinking, text: nil), FakeBlock.new(type: :text, text: %({"columns": [1]})) ],
                    model: "claude-haiku-5-5", stop_reason: :end_turn, usage: FakeUsage.new(input_tokens: 1234, output_tokens: 56))
  end
  let(:client) do
    recorded = calls
    answer = -> { reply }
    messages = Object.new
    messages.define_singleton_method(:create) do |**params|
      recorded << params
      result = answer.call
      result.is_a?(Exception) ? raise(result) : result
    end
    Struct.new(:messages).new(messages)
  end
  let(:adapter) { described_class.new(model: "claude-haiku-5-5", client: client) }

  def status_error(klass, status)
    klass.new(url: "https://api.anthropic.com/v1/messages", status: status, headers: { "x-api-key" => "sk-ant-secret" },
              body: { error: { message: "sk-ant-secret を含む本文" } }, request: nil, response: nil)
  end

  describe "#complete" do
    it "指示文は system_ に、入力は user の message に入る。モデルと、出力の上限を送る" do
      adapter.complete(instructions: "指示文", input: "候補の項目と問い")

      expect(calls).to eq([ { model: "claude-haiku-5-5", max_tokens: described_class::MAX_TOKENS, system_: "指示文",
                              messages: [ { role: "user", content: "候補の項目と問い" } ] } ])
    end

    it "応答の本文（text の部分だけ）と、モデルの名前、トークンの数を返す" do
      response = adapter.complete(instructions: "指示文", input: "問い")

      expect(response.text).to eq(%({"columns": [1]}))
      expect(response.model).to eq("claude-haiku-5-5")
      expect(response.input_tokens).to eq(1234)
      expect(response.output_tokens).to eq(56)
    end

    context "うまくいかないとき（どれも Llm::Error。理由に、鍵・ヘッダ・本文は入らない）" do
      def failure
        adapter.complete(instructions: "指示文", input: "問い")
        nil
      rescue Llm::Error => e
        e.message
      end

      it "断り（stop_reason が refusal）" do
        reply.stop_reason = :refusal
        expect(failure).to eq("モデルが、応答を断りました。")
      end

      it "出力の上限で、応答が途中で切れた" do
        reply.stop_reason = :max_tokens
        expect(failure).to eq("応答が、出力の上限で途中で切れました。")
      end

      it "本文が空" do
        reply.content = []
        expect(failure).to eq("応答に、本文がありません。")
      end

      context "SDK の例外" do
        let(:error) { nil }
        let(:reply) { error }

        {
          "時間切れ" => [ -> { Anthropic::Errors::APITimeoutError.new(url: "https://api.anthropic.com/v1/messages") }, "API の応答が、時間切れになりました。" ],
          "通信の失敗" => [ -> { Anthropic::Errors::APIConnectionError.new(url: "https://api.anthropic.com/v1/messages") }, "API に、つながりませんでした。" ]
        }.each do |name, (build, message)|
          context name do
            let(:error) { build.call }

            it { expect(failure).to eq(message) }
          end
        end

        context "回数の制限（429）" do
          let(:error) { status_error(Anthropic::Errors::RateLimitError, 429) }

          it { expect(failure).to eq("API の回数の制限に当たりました（429）。") }
        end

        context "鍵が受け付けられない（401）" do
          let(:error) { status_error(Anthropic::Errors::AuthenticationError, 401) }

          it "理由に、鍵・ヘッダ・本文は入らない" do
            expect(failure).to eq("API の鍵が、受け付けられませんでした（401）。")
            expect(failure).not_to include("sk-ant")
          end
        end

        context "そのほかの状態（400、500 など）" do
          let(:error) { status_error(Anthropic::Errors::BadRequestError, 400) }

          it { expect(failure).to eq("API が、エラーを返しました（400）。") }
        end

        context "SDK のそのほかの例外" do
          let(:error) { Anthropic::Errors::ConversionError.allocate }

          it { expect(failure).to eq("API の呼び出しに失敗しました（ConversionError）。") }
        end
      end
    end
  end

  it "名前は anthropic。外に文を送る" do
    expect(adapter.name).to eq("anthropic")
    expect(adapter).to be_external
  end

  it "inspect に、鍵は出ない" do
    real = described_class.build("ANTHROPIC_API_KEY" => "sk-ant-not-a-real-key", "ANLAGE_LLM_MODEL" => "claude-haiku-5-5").first

    expect(real.inspect).not_to include("sk-ant")
  end

  describe ".build（環境変数から作る。[アダプタ, nil] か [nil, 使えない理由]）" do
    it "鍵と、モデルの名前がそろうと、アダプタができる（作るだけでは、外を呼ばない）" do
      adapter, reason = described_class.build("ANTHROPIC_API_KEY" => "sk-ant-not-a-real-key", "ANLAGE_LLM_MODEL" => "claude-haiku-5-5")

      expect(adapter).to be_a(described_class)
      expect(adapter.model).to eq("claude-haiku-5-5")
      expect(reason).to be_nil
    end

    it "鍵が無いときは、使えない。理由が付く" do
      expect(described_class.build("ANLAGE_LLM_MODEL" => "claude-haiku-5-5")).to eq([ nil, "API の鍵（ANTHROPIC_API_KEY）がありません。" ])
      expect(described_class.build("ANTHROPIC_API_KEY" => " ", "ANLAGE_LLM_MODEL" => "claude-haiku-5-5").first).to be_nil
    end

    it "モデルの名前が無いときは、使えない（既定のモデルは置かない）" do
      expect(described_class.build("ANTHROPIC_API_KEY" => "sk-ant-not-a-real-key"))
        .to eq([ nil, "モデルの名前（ANLAGE_LLM_MODEL）がありません。" ])
    end
  end
end
