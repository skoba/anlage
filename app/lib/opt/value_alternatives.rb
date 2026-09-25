module Opt
  # ELEMENT の value 属性が持つ代替 RM 型の一覧を field の path をキーに返す
  # （skoba/anlage#33）。走査は Opt::ElementConstraints（#34 で占有率下限と統合）。
  #
  # gem の FieldExtractor は代替のうち C_CODE_REFERENCE を持つものを主型に選ぶだけで、
  # 代替の存在を field に載せない（gem 側の還流候補は docs/upstream-candidates.md 19 項）。
  class ValueAlternatives
    def self.call(opt)
      Opt::ElementConstraints.call(opt).transform_values { |c| c.fetch("alternatives") }
    end
  end
end
