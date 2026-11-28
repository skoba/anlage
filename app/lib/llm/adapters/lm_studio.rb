require "json"
require "net/http"
require "uri"

module Llm
  module Adapters
    # LM Studio（同じ機械の中）の手元のモデルのアダプタ（docs/design/s4-nl-aql-plan.md 15 節。R-20261128-5）。
    # OpenAI と同じ形の口（POST <接続先>/chat/completions）。文を送って、文を受け取るだけ。
    # 接続先は、開発機の中（127.0.0.1、localhost、::1）だけ。外に送らない。
    #
    # 口の形は、LM Studio の公式の文書で確かめた（2026-11-28。lmstudio.ai/docs/developer の openai-compat/chat-completions、
    # openai-compat/structured-output、core/authentication、api-changelog。計画書 15.2 節）:
    #   本文: model、messages（system と user）、stream、max_tokens、temperature、seed、
    #         response_format（{ type: "json_schema", json_schema: { name:, schema: } }。出力の形を縛る）
    #   ヘッダ: Authorization: Bearer <トークン>（LM Studio の「Require Authentication」がオンのときだけ要る）
    #   応答: choices[0].message.content、choices[0].finish_reason、model、usage.prompt_tokens／completion_tokens
    # 文書に無いので、送らないもの: 考える分（reasoning）の指定。この口には、止める項目が書かれていない（計画書 15.2 節）。
    # 考える分が、本文と別の項目（message.reasoning、reasoning_content）で返ることは、変更の履歴に書かれている。本文としては読まない。
    class LmStudio
      DEFAULT_BASE_URL = "http://127.0.0.1:1234/v1".freeze
      # 出力の上限。選択の JSON は 60〜80 トークン（Ollama での実測）。AQL を書かせる腕と、考える分が出たときの余裕を見る
      MAX_TOKENS = 1000
      # GPU の無い機械では、モデルを読み込んだ直後の 1 問めに、分の単位でかかる（Ollama での実測）
      TIMEOUT_IN_SECONDS = 300
      # response_format の json_schema.name。文書の例は、どれも名前を付けている。中身の意味は無い
      SCHEMA_NAME = "output".freeze

      attr_reader :model, :base_url

      # 環境変数から作る。[アダプタ, nil] か [nil, 使えない理由]。options は、温度と乱数の種（測定のとき）
      def self.build(env, options = {})
        model = env["ANLAGE_LLM_MODEL"].to_s.strip
        base_url = env["ANLAGE_LLM_BASE_URL"].to_s.strip.then { |url| url.empty? ? DEFAULT_BASE_URL : url }
        uri = Openai.parse(base_url)
        return [ nil, "接続先（ANLAGE_LLM_BASE_URL）が、URL として読めません。" ] unless uri
        return [ nil, "lmstudio の接続先（ANLAGE_LLM_BASE_URL）は、開発機の中（127.0.0.1、localhost）だけです。" ] unless Openai.local?(uri)
        return [ nil, "モデルの名前（ANLAGE_LLM_MODEL）がありません。" ] if model.empty?

        [ new(model: model, base_url: base_url, api_token: env["LM_API_TOKEN"].to_s.strip, **options), nil ]
      end

      def initialize(model:, base_url: DEFAULT_BASE_URL, api_token: nil, timeout: TIMEOUT_IN_SECONDS, temperature: nil, seed: nil)
        @model = model
        @base_url = base_url
        @api_token = api_token.to_s
        @uri = URI.parse("#{base_url.chomp('/')}/chat/completions")
        @timeout = timeout
        @sampling = { temperature: temperature, seed: seed }.compact
      end

      def name = "lmstudio"
      def external? = !Openai.local?(@uri)
      def inspect = "#<#{self.class.name} model=#{@model.inspect} base_url=#{@base_url.inspect}>"

      def complete(instructions:, input:, json_schema: nil)
        payload = { model: @model, stream: false, max_tokens: MAX_TOKENS, **@sampling,
                    messages: [ { role: "system", content: instructions }, { role: "user", content: input } ] }
        payload[:response_format] = { type: "json_schema", json_schema: { name: SCHEMA_NAME, schema: json_schema } } if json_schema
        status, body = post(payload)
        raise Error, status_failure(status) unless status == 200

        data = JSON.parse(body)
        choice = data.fetch("choices").fetch(0)
        message = choice.fetch("message")
        raise Error, "応答が、出力の上限で途中で切れました。" if choice["finish_reason"] == "length"
        raise Error, blank_failure(message) if message["content"].to_s.strip.empty?

        usage = data["usage"] || {}
        Response.new(text: message["content"], model: data["model"],
                     input_tokens: usage["prompt_tokens"], output_tokens: usage["completion_tokens"])
      rescue JSON::ParserError, KeyError, IndexError, TypeError, NoMethodError
        raise Error, "LM Studio の応答が、読めませんでした。"
      end

      private

      # [状態の番号, 本文]。通信の失敗は Llm::Error（例外の文は使わない）
      def post(payload)
        request = Net::HTTP::Post.new(@uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{@api_token}" unless @api_token.empty?
        request.body = JSON.generate(payload)
        response = Net::HTTP.start(@uri.host, @uri.port, open_timeout: @timeout, read_timeout: @timeout, write_timeout: @timeout) do |http|
          http.request(request)
        end
        [ response.code.to_i, response.body.to_s.force_encoding("UTF-8") ]
      rescue Timeout::Error
        raise Error, "LM Studio の応答が、時間切れになりました。"
      rescue SocketError, SystemCallError, IOError
        raise Error, "LM Studio に、つながりませんでした。サーバーが立っているかを確かめてください。"
      end

      def blank_failure(message)
        thought = message["reasoning"].to_s + message["reasoning_content"].to_s
        thought.strip.empty? ? "応答に、本文がありません。" : "考える分だけが返り、本文がありません。"
      end

      def status_failure(status)
        return "LM Studio が、API のトークンを受け付けませんでした（401）。LM_API_TOKEN を確かめてください。" if status == 401

        "LM Studio が、エラーを返しました（#{status}）。"
      end
    end
  end
end
