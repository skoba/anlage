require "json"
require "net/http"
require "uri"

module Llm
  module Adapters
    # 手元で動くモデルのアダプタ（docs/design/s4-nl-aql-plan.md 14 節。R-20261127-29）。Ollama の元の口（POST /api/chat）。
    # 文を送って、文を受け取るだけ。接続先は、開発機の中（127.0.0.1、localhost、::1）だけ。外に送らない。鍵は無い。
    #
    # 口の形は、公式の文書（docs.ollama.com の api/chat、capabilities/thinking、structured-outputs）と、開発機での試し
    # （docs/reports/s4-local-model-candidates.md。Ollama 0.40.18、qwen3:4b）で確かめた:
    #   本文: model、messages（system と user）、stream: false、think: false（考える分を出さない）、
    #         format（JSON スキーマ。出力の形を縛る）、options（num_predict、temperature、seed）
    #   応答: message.content、model、done_reason、prompt_eval_count、eval_count
    # OpenAI と同じ形の口（/v1/chat/completions）を使わないのは、そちらでは考える分が止まらず、1 問に 4 分かかったため（実測）。
    # 出力の形を縛らないと、このモデルは本文に考えを書いて、JSON として読めない（実測: 0/3）。
    class Local
      DEFAULT_BASE_URL = "http://127.0.0.1:11434".freeze
      # 出力の上限。選択の JSON は 60〜80 トークン（実測）
      MAX_TOKENS = 400
      # CPU だけの機械では、入力を読むだけで 1 分ほどかかる（実測）
      TIMEOUT_IN_SECONDS = 300

      attr_reader :model, :base_url

      # 環境変数から作る。[アダプタ, nil] か [nil, 使えない理由]。options は、温度と乱数の種（測定のとき）
      def self.build(env, options = {})
        model = env["ANLAGE_LLM_MODEL"].to_s.strip
        base_url = env["ANLAGE_LLM_BASE_URL"].to_s.strip.then { |url| url.empty? ? DEFAULT_BASE_URL : url }
        uri = Openai.parse(base_url)
        return [ nil, "接続先（ANLAGE_LLM_BASE_URL）が、URL として読めません。" ] unless uri
        return [ nil, "local の接続先（ANLAGE_LLM_BASE_URL）は、開発機の中（127.0.0.1、localhost）だけです。" ] unless Openai.local?(uri)
        return [ nil, "モデルの名前（ANLAGE_LLM_MODEL）がありません。" ] if model.empty?

        [ new(model: model, base_url: base_url, **options), nil ]
      end

      def initialize(model:, base_url: DEFAULT_BASE_URL, timeout: TIMEOUT_IN_SECONDS, temperature: nil, seed: nil)
        @model = model
        @base_url = base_url
        @uri = URI.parse("#{base_url.chomp('/')}/api/chat")
        @timeout = timeout
        @options = { num_predict: MAX_TOKENS, temperature: temperature, seed: seed }.compact
      end

      def name = "local"
      def external? = false

      def complete(instructions:, input:, json_schema: nil)
        payload = { model: @model, stream: false, think: false, options: @options,
                    messages: [ { role: "system", content: instructions }, { role: "user", content: input } ] }
        payload[:format] = json_schema if json_schema
        status, body = post(payload)
        raise Error, status_failure(status) unless status == 200

        data = JSON.parse(body)
        text = data.fetch("message").fetch("content").to_s
        raise Error, "応答が、出力の上限で途中で切れました。" if data["done_reason"] == "length"
        raise Error, "応答に、本文がありません。" if text.strip.empty?

        Response.new(text: text, model: data["model"], input_tokens: data["prompt_eval_count"], output_tokens: data["eval_count"])
      rescue JSON::ParserError, KeyError, TypeError, NoMethodError
        raise Error, "手元のモデルの応答が、読めませんでした。"
      end

      private

      def post(payload)
        request = Net::HTTP::Post.new(@uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
        response = Net::HTTP.start(@uri.host, @uri.port, open_timeout: @timeout, read_timeout: @timeout, write_timeout: @timeout) do |http|
          http.request(request)
        end
        [ response.code.to_i, response.body.to_s.force_encoding("UTF-8") ]
      rescue Timeout::Error
        raise Error, "手元のモデルの応答が、時間切れになりました。"
      rescue SocketError, SystemCallError, IOError
        raise Error, "手元のモデルに、つながりませんでした。"
      end

      def status_failure(status)
        return "手元のモデルが、見つかりませんでした（404）。モデルの名前と、入れてあるかを確かめてください。" if status == 404

        "手元のモデルが、エラーを返しました（#{status}）。"
      end
    end
  end
end
