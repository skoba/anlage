require "json"
require "net/http"
require "uri"

module Llm
  module Adapters
    # OpenAI の Chat Completions の口のアダプタ（docs/design/s4-nl-aql-plan.md 11 節。R-20261127-25）。文を送って、文を受け取るだけ。
    # gem を足さず、標準の Net::HTTP で呼ぶ。口の形は、公式の文書で確かめた（docs/reports/s4-nl-query-log.md R5）:
    #   POST <接続先>/chat/completions、ヘッダ Authorization: Bearer <鍵>
    #   本文: model、messages（role は system と user）、max_completion_tokens
    #   応答: choices[0].message.content／refusal、choices[0].finish_reason（stop／length／content_filter…）、model、
    #         usage.prompt_tokens／completion_tokens
    #
    # 接続先（base_url）は変えられる。開発機の中（127.0.0.1、localhost、::1）のときだけ、「外に送らない」扱いにする。
    # 鍵は、ヘッダに入れるだけ。理由、inspect に、鍵・応答の本文を出さない。
    class Openai
      DEFAULT_BASE_URL = "https://api.openai.com/v1".freeze
      LOCAL_HOSTS = %w[127.0.0.1 localhost ::1 [::1]].freeze
      # 出力の上限（考える分を含む）。待ち時間は、画面の 1 回の問い合わせを長く待たせない値。やり直しはしない
      MAX_TOKENS = 2000
      TIMEOUT_IN_SECONDS = 30

      attr_reader :model, :base_url

      # 環境変数から作る。[アダプタ, nil] か [nil, 使えない理由]。作るだけでは、外を呼ばない
      def self.build(env)
        key = env["OPENAI_API_KEY"].to_s.strip
        model = env["ANLAGE_LLM_MODEL"].to_s.strip
        base_url = env["ANLAGE_LLM_BASE_URL"].to_s.strip.then { |url| url.empty? ? DEFAULT_BASE_URL : url }
        uri = parse(base_url)
        return [ nil, "接続先（ANLAGE_LLM_BASE_URL）が、URL として読めません。" ] unless uri
        return [ nil, "接続先（ANLAGE_LLM_BASE_URL）が、開発機の外なのに https ではありません。" ] if !local?(uri) && uri.scheme != "https"
        return [ nil, "API の鍵（OPENAI_API_KEY）がありません。" ] if key.empty? && !local?(uri)
        # 既定のモデルは置かない。どれを推すかは、測定の結果で決める（計画書 3.2 節）
        return [ nil, "モデルの名前（ANLAGE_LLM_MODEL）がありません。" ] if model.empty?

        [ new(model: model, api_key: key, base_url: base_url), nil ]
      end

      def self.parse(url)
        uri = URI.parse(url)
        uri.is_a?(URI::HTTP) && uri.host.to_s != "" ? uri : nil
      rescue URI::InvalidURIError
        nil
      end

      def self.local?(uri) = LOCAL_HOSTS.include?(uri.host.to_s.downcase)

      def initialize(model:, api_key:, base_url: DEFAULT_BASE_URL, timeout: TIMEOUT_IN_SECONDS)
        @model = model
        @api_key = api_key
        @base_url = base_url
        @uri = URI.parse("#{base_url.chomp('/')}/chat/completions")
        @timeout = timeout
      end

      def name = "openai"
      def external? = !self.class.local?(@uri)
      def inspect = "#<#{self.class.name} model=#{@model.inspect} base_url=#{@base_url.inspect}>"

      def complete(instructions:, input:)
        status, body = post(model: @model, max_completion_tokens: MAX_TOKENS,
                            messages: [ { role: "system", content: instructions }, { role: "user", content: input } ])
        raise Error, status_failure(status) unless status == 200

        data = JSON.parse(body)
        choice = data.fetch("choices").fetch(0)
        message = choice.fetch("message")
        raise Error, "モデルが、応答を断りました。" if message["refusal"].present? || choice["finish_reason"] == "content_filter"
        raise Error, "応答が、出力の上限で途中で切れました。" if choice["finish_reason"] == "length"
        raise Error, "応答に、本文がありません。" if message["content"].to_s.strip.empty?

        usage = data["usage"] || {}
        Response.new(text: message["content"], model: data["model"],
                     input_tokens: usage["prompt_tokens"], output_tokens: usage["completion_tokens"])
      rescue JSON::ParserError, KeyError, IndexError, TypeError, NoMethodError
        raise Error, "API の応答が、読めませんでした。"
      end

      private

      # [状態の番号, 本文]。通信の失敗は Llm::Error（例外の文は使わない）
      def post(payload)
        request = Net::HTTP::Post.new(@uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{@api_key}" unless @api_key.to_s.empty?
        request.body = JSON.generate(payload)
        response = Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == "https",
                                                         open_timeout: @timeout, read_timeout: @timeout, write_timeout: @timeout) do |http|
          http.request(request)
        end
        [ response.code.to_i, response.body.to_s.force_encoding("UTF-8") ]
      rescue Timeout::Error
        raise Error, "API の応答が、時間切れになりました。"
      rescue SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError
        raise Error, "API に、つながりませんでした。"
      end

      def status_failure(status)
        case status
        when 401 then "API の鍵が、受け付けられませんでした（401）。"
        when 429 then "API の回数の制限に当たりました（429）。"
        else "API が、エラーを返しました（#{status}）。"
        end
      end
    end
  end
end
