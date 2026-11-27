require "json"

module Llm
  # LLM を呼んだ回数と、トークンの数（docs/design/s4-nl-aql-plan.md 10.3 節。費用の歯止め）。
  # 日ごとに、ファイル（既定は storage/llm_usage.json）に数える。表は足さない。書くときはファイルをロックする。
  # ファイルに書くのは、日付と数だけ（問いの文も、応答も書かない）。
  class Usage
    ZERO = { calls: 0, input_tokens: 0, output_tokens: 0 }.freeze

    def self.default
      new(path: Rails.root.join("storage/llm_usage.json"))
    end

    def initialize(path:, clock: -> { Time.zone.today })
      @path = Pathname(path)
      @clock = clock
    end

    # きょうの数。ファイルが無い、読めないときは 0
    def today
      (read || {}).fetch(key, {}).then { |counts| ZERO.keys.to_h { |name| [ name, counts[name.to_s].to_i ] } }
    end

    # きょうの回数が上限に達したか。ファイルが読めないときは、達した扱いにする（数えられないまま呼ばない）
    def exhausted?(limit)
      counts = read
      counts.nil? || counts.fetch(key, {})["calls"].to_i >= limit
    end

    # 1 回の呼び出しを数える。response は Llm::Response か、失敗したときは nil
    def record(response)
      @path.dirname.mkpath
      File.open(@path, File::RDWR | File::CREAT, 0o644) do |file|
        file.flock(File::LOCK_EX)
        counts = parse(file.read)
        next if counts.nil?

        day = counts[key] ||= {}
        day["calls"] = day["calls"].to_i + 1
        day["input_tokens"] = day["input_tokens"].to_i + response&.input_tokens.to_i
        day["output_tokens"] = day["output_tokens"].to_i + response&.output_tokens.to_i
        file.rewind
        file.truncate(0)
        file.write(JSON.generate(counts))
      end
    end

    private

    def key = @clock.call.iso8601

    def read
      @path.file? ? parse(@path.read) : {}
    end

    # 読めないときは nil
    def parse(text)
      return {} if text.to_s.strip.empty?

      data = JSON.parse(text)
      data.is_a?(Hash) ? data : nil
    rescue JSON::ParserError
      nil
    end
  end
end
