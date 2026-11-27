module Definitions
  # 検査の問題 1 件（docs/design/definition-layer-plan.md 2.3、skoba/anlage#257）。機械が読む形（to_h）と、人が読む文（to_s）の両方を出す。
  # severity: :error（置けない）か :draft（D8。案として試せるが保存には効かない）
  Problem = Data.define(:code, :definition, :pointer, :id, :message, :candidates, :severity) do
    def initialize(code:, definition:, message:, pointer: "", id: nil, candidates: [], severity: :error)
      super
    end

    def error? = severity == :error

    def to_h
      { code:, definition:, pointer:, id:, message:, candidates:, severity: severity.to_s }.compact
    end

    def to_s
      place = [ definition, pointer.presence ].compact.join(": ")
      text = "#{place}: #{message}  [#{code}]"
      candidates.any? ? "#{text}\n  候補: #{candidates.join('、')}" : text
    end
  end
end
