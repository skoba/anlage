module Llm
  module Adapters
    # Claude API のアダプタ（docs/design/s4-nl-aql-plan.md 7 節の段 4）。文を送って、文を受け取るだけ。
    # 公式の SDK（gem anthropic）を使う。gem は、起動のときには読み込まず、ここで読む。
    #
    # SDK の呼び方は、gem anthropic 2.14.0 のソースで確かめた（docs/reports/s4-nl-query-log.md R4）:
    #   ::Anthropic::Client.new(api_key:, timeout:, max_retries:)       lib/anthropic/client.rb
    #   client.messages.create(model:, max_tokens:, system_:, messages:) lib/anthropic/resources/messages.rb（system は system_）
    #   応答: content（type が :text の部分に text）、model、stop_reason、usage.input_tokens／output_tokens
    #   例外: ::Anthropic::Errors::APITimeoutError < APIConnectionError < APIError、APIStatusError#status
    #
    # 鍵は、SDK のクライアントに渡すだけで、ここには持たない。例外の文、理由、inspect に、鍵・ヘッダ・本文を出さない。
    class Anthropic
      # 出力の上限（考える分を含む）。選択の JSON は小さい
      MAX_TOKENS = 2000
      # 画面の 1 回の問い合わせを、長く待たせない（SDK の既定は 600 秒、やり直し 2 回）
      TIMEOUT_IN_SECONDS = 30
      MAX_RETRIES = 1

      attr_reader :model

      # 環境変数から作る。[アダプタ, nil] か [nil, 使えない理由]。作るだけでは、外を呼ばない
      def self.build(env)
        key = env["ANTHROPIC_API_KEY"].to_s.strip
        model = env["ANLAGE_LLM_MODEL"].to_s.strip
        return [ nil, "API の鍵（ANTHROPIC_API_KEY）がありません。" ] if key.empty?
        # 既定のモデルは置かない。どれを推すかは、測定の結果で決める（計画書 3.2 節）
        return [ nil, "モデルの名前（ANLAGE_LLM_MODEL）がありません。" ] if model.empty?

        require "anthropic"
        client = ::Anthropic::Client.new(api_key: key, timeout: TIMEOUT_IN_SECONDS, max_retries: MAX_RETRIES)
        [ new(model: model, client: client), nil ]
      rescue LoadError
        [ nil, "gem anthropic が入っていません。" ]
      end

      def initialize(model:, client:)
        @model = model
        @client = client
      end

      def name = "anthropic"
      def external? = true
      def inspect = "#<#{self.class.name} model=#{@model.inspect}>"

      # json_schema（出力の形）は受けるだけで、まだ使わない（output_config.format で縛れるかは、鍵が渡ったときに確かめる。R-20261127-29）
      def complete(instructions:, input:, json_schema: nil)
        message = @client.messages.create(model: @model, max_tokens: MAX_TOKENS, system_: instructions,
                                          messages: [ { role: "user", content: input } ])
        raise Error, "モデルが、応答を断りました。" if message.stop_reason == :refusal
        raise Error, "応答が、出力の上限で途中で切れました。" if message.stop_reason == :max_tokens

        text = message.content.select { |block| block.type == :text }.map(&:text).join
        raise Error, "応答に、本文がありません。" if text.strip.empty?

        Response.new(text: text, model: message.model.to_s,
                     input_tokens: message.usage.input_tokens, output_tokens: message.usage.output_tokens)
      rescue ::Anthropic::Errors::Error => e
        raise Error, failure(e)
      end

      private

      # SDK の例外 → 理由。例外の文（URL、本文を含む）は使わない
      def failure(error)
        case error
        when ::Anthropic::Errors::APITimeoutError then "API の応答が、時間切れになりました。"
        when ::Anthropic::Errors::APIConnectionError then "API に、つながりませんでした。"
        when ::Anthropic::Errors::RateLimitError then "API の回数の制限に当たりました（429）。"
        when ::Anthropic::Errors::AuthenticationError then "API の鍵が、受け付けられませんでした（401）。"
        when ::Anthropic::Errors::APIStatusError then "API が、エラーを返しました（#{error.status.to_i}）。"
        else "API の呼び出しに失敗しました（#{error.class.name.demodulize}）。"
        end
      end
    end
  end
end
