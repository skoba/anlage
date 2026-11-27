module Llm
  # LLM のオンとオフ（docs/design/s4-nl-aql-plan.md 10.1 節。R-20261127-14）。運用する人が、環境変数で決める。
  #   ANLAGE_LLM                    アダプタの名前。これがオンの設定。無い・空・off はオフ
  #   ANLAGE_LLM_DAILY_CALL_LIMIT   1 日に呼んでよい回数（既定 100）
  #   ANLAGE_LLM_RECORDINGS         記録した応答のディレクトリ（recorded のとき）
  # オンになるのは、ANLAGE_LLM と、そのアダプタが要るもの（鍵など）の両方がそろったときだけ。鍵だけではオンにならない。
  # 鍵の値は持たない（アダプタを作るところで環境変数から読み、ここには残さない）。reason にも出さない。
  class Settings
    DEFAULT_DAILY_CALL_LIMIT = 100
    # 段 4（anthropic）、段 5（local）で足す。それまでは、名前を書いてもオフ
    PLANNED = %w[anthropic local].freeze

    attr_reader :adapter, :adapter_name, :reason, :daily_call_limit

    def self.from_env(env = ENV)
      name = env["ANLAGE_LLM"].to_s.strip.downcase
      limit = daily_call_limit(env["ANLAGE_LLM_DAILY_CALL_LIMIT"])
      return new(daily_call_limit: limit) if name.empty? || name == "off"

      adapter, reason = build(name, env)
      new(adapter: adapter, adapter_name: name, reason: reason, daily_call_limit: limit)
    end

    # [アダプタ, nil] か [nil, オフになる理由]
    def self.build(name, env)
      return [ nil, "このアダプタは、まだ使えません（#{name}）。" ] if PLANNED.include?(name)
      return [ nil, "知らないアダプタの名前です（#{name.truncate(40)}）。" ] unless name == "recorded"

      dir = env["ANLAGE_LLM_RECORDINGS"].to_s
      return [ nil, "記録した応答のディレクトリ（ANLAGE_LLM_RECORDINGS）がありません。" ] unless !dir.empty? && File.directory?(dir)

      [ Adapters::Recorded.new(dir: dir), nil ]
    end

    def self.daily_call_limit(raw)
      raw.to_s.strip.match?(/\A\d+\z/) ? raw.to_i : DEFAULT_DAILY_CALL_LIMIT
    end

    def initialize(adapter: nil, adapter_name: nil, reason: nil, daily_call_limit: DEFAULT_DAILY_CALL_LIMIT)
      @adapter = adapter
      @adapter_name = adapter_name
      @reason = reason
      @daily_call_limit = daily_call_limit
    end

    def on? = !@adapter.nil?
    def external? = on? && @adapter.external?
  end
end
