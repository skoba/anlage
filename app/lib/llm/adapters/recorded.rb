require "json"

module Llm
  module Adapters
    # 記録した応答を返す（docs/design/s4-nl-aql-plan.md 7 節）。spec と CI と、測定の再現に使う。外を呼ばない。
    # 記録は <dir>/<送った文の sha256>.json（1 つの文に 1 ファイル）。指示文やカードの文を変えると sha256 が変わり、
    # 記録に当たらなくなる（黙って古い応答を使わない）。
    #   { "sha256":, "input":, "response":, "model":, "input_tokens":, "output_tokens":, "source": }
    class Recorded
      def initialize(dir:)
        @dir = Pathname(dir)
      end

      def name = "recorded"
      def external? = false

      def complete(instructions:, input:)
        sha256 = Llm.fingerprint(instructions: instructions, input: input)
        path = @dir.join("#{sha256}.json")
        raise Error, "記録が無い（#{sha256[0, 12]}）" unless path.file?

        record = JSON.parse(path.read)
        Response.new(text: record.fetch("response"), model: record["model"],
                     input_tokens: record["input_tokens"], output_tokens: record["output_tokens"])
      rescue JSON::ParserError, KeyError
        raise Error, "記録が読めない（#{sha256[0, 12]}）"
      end
    end
  end
end
