module Definitions
  # D1: 書式（スキーマ）の検査器（docs/design/definition-layer-plan.md 2.1・2.2、skoba/anlage#257）。gem を足さない。
  # 正はこの検査器で、公開用の JSON Schema は、ここから書き出す写し（R-20261127-21 の回答 2。書き出しは D-2）。
  # 書式の説明は docs/reports/definitions-log.md R1
  module Schema
    COMPONENTS = %w[problem_list time_series lab_table records form table buttons].freeze
    # 記録を引く部品。from が要る（全体から引くなら from: { auto: true }。R-20261128-7 の回答 4、skoba/anlage#281）
    RECORD_COMPONENTS = %w[problem_list time_series lab_table records table].freeze
    # auto と一緒に書けるのは rm_type だけ（records の絞り込み。依頼と紹介状 = INSTRUCTION）
    AUTO_WITH = %w[auto rm_type].freeze

    def self.string = { type: :string }
    def self.integer = { type: :integer }
    def self.boolean = { type: :boolean }
    def self.enum(*values) = { type: :enum, values: values.flatten }
    def self.array(of) = { type: :array, of: }
    def self.object(required: {}, optional: {}, rule: nil) = { type: :object, required:, optional:, rule: }
    def self.one_of_keys(keys, message) = ->(hash) { message unless keys.count { hash.key?(_1) } == 1 }

    SCREEN_REF = object(required: { "screen" => string })
    THEN = object(optional: { "screen" => string, "record" => enum("saved") },
                  rule: one_of_keys(%w[screen record], "then には screen か record のどちらか 1 つが要る"))
    OPEN = object(optional: { "form" => string, "screen" => string, "then" => THEN },
                  rule: one_of_keys(%w[form screen], "open には form か screen のどちらか 1 つが要る"))
    BUTTON = object(required: { "id" => string, "label" => string, "open" => OPEN })
    # auto: true は「U1 の規則で、登録済みのテンプレート全体から引く」（docs/design/definition-registration-plan.md 3 節）
    FROM = object(optional: { "auto" => enum(true), "template" => string, "archetype" => string, "field" => string,
                              "fields" => array(string), "rm_type" => string },
                  rule: lambda { |hash|
                    others = hash.keys - AUTO_WITH
                    "from の auto は rm_type のほかのキーと一緒に書けない（#{others.join('、')}）" if hash.key?("auto") && others.any?
                  })
    SECTION = object(required: { "id" => string, "component" => enum(COMPONENTS) },
                     optional: { "from" => FROM, "columns" => array(string), "series_key" => string, "only" => array(string),
                                 "chart" => enum("line"), "items" => array(BUTTON) },
                     rule: lambda { |hash|
                       next unless RECORD_COMPONENTS.include?(hash["component"]) && !hash.key?("from")

                       "#{hash['component']} には from が要る。登録済みのテンプレート全体から引くなら from: { auto: true } と書く"
                     })
    CASE = object(optional: { "when" => string, "value" => string, "else" => string },
                  rule: ->(hash) { "cases の要素は when と value、または else だけ" unless hash.keys.sort == %w[value when] || hash.keys == %w[else] })
    RULE = object(required: { "id" => string, "target" => string },
                  optional: { "inputs" => array(string), "formula" => string, "cases" => array(CASE), "round" => integer,
                              "on" => enum("input", "save"), "editable" => boolean },
                  rule: one_of_keys(%w[formula cases], "rule には formula か cases のどちらか 1 つが要る"))

    KINDS = {
      "bundle" => object(required: { "bundle" => string, "version" => string, "title" => string },
                         optional: { "templates" => array(object(required: { "template_id" => string }, optional: { "version" => string })),
                                     "screens" => array(string), "logic" => array(string), "flows" => array(string), "start" => SCREEN_REF },
                         rule: ->(hash) { "screens があるときは start が要る" if hash["screens"].present? && !hash.key?("start") }),
      "screen" => object(required: { "screen" => string, "version" => string, "sections" => array(SECTION) },
                         optional: { "title" => string, "applies_to" => enum("patient") }),
      "logic" => object(required: { "logic" => string, "version" => string, "template" => string, "rules" => array(RULE) },
                        optional: { "source" => string, "reviewed_by" => string })
    }.freeze

    TYPE_NAMES = { string: "文字列", integer: "整数", boolean: "真偽（true か false）", array: "配列", object: "対応表（キー: 値）" }.freeze

    module_function

    # 公開用の JSON Schema（draft 2020-12）を書き出す。写しなので、対の規則（rule）は description に文で書く。食い違ったら検査器が正
    def to_json_schema(kind)
      json_schema(KINDS.fetch(kind))
    end

    def json_schema(schema)
      case schema[:type]
      when :string then { "type" => "string" }
      when :integer then { "type" => "integer" }
      when :boolean then { "type" => "boolean" }
      when :enum then { "enum" => schema[:values] }
      when :array then { "type" => "array", "items" => json_schema(schema[:of]) }
      when :object
        properties = schema[:required].merge(schema[:optional]).transform_values { json_schema(_1) }
        { "type" => "object", "required" => schema[:required].keys, "properties" => properties, "additionalProperties" => false }
          .merge(schema[:rule] ? { "description" => "ほかの規則は検査器（Definitions::Schema）が正" } : {})
      end
    end

    def check(kind, data, definition:)
      problems = []
      walk(KINDS.fetch(kind), data, "", nil, nil, definition, problems)
      problems
    end

    def walk(schema, value, pointer, key, id, definition, problems)
      add = ->(message, candidates = []) { problems << Problem.new(code: "D1", definition:, pointer:, id:, message:, candidates:) }
      case schema[:type]
      when :string then add.("#{key} は#{TYPE_NAMES[:string]}でなければならない") unless value.is_a?(String)
      when :integer then add.("#{key} は#{TYPE_NAMES[:integer]}でなければならない") unless value.is_a?(Integer)
      when :boolean then add.("#{key} は#{TYPE_NAMES[:boolean]}でなければならない") unless [ true, false ].include?(value)
      when :enum then add.("#{key} に #{value.inspect} は使えない", schema[:values]) unless schema[:values].include?(value)
      when :array
        return add.("#{key} は#{TYPE_NAMES[:array]}でなければならない") unless value.is_a?(Array)

        value.each_with_index { |item, index| walk(schema[:of], item, "#{pointer}/#{index}", key, id, definition, problems) }
      when :object then walk_object(schema, value, pointer, key, id, definition, problems, add)
      end
    end

    def walk_object(schema, value, pointer, key, id, definition, problems, add)
      return add.("#{key || '最上位'} は#{TYPE_NAMES[:object]}でなければならない") unless value.is_a?(Hash)

      id = value["id"] if value["id"].is_a?(String)
      known = schema[:required].merge(schema[:optional])
      schema[:required].each_key do |name|
        problems << Problem.new(code: "D1", definition:, pointer:, id:, message: "必須のキー #{name} が無い") unless value.key?(name)
      end
      value.each do |name, child|
        child_pointer = "#{pointer}/#{name}"
        next walk(known[name], child, child_pointer, name, id, definition, problems) if known.key?(name)

        problems << Problem.new(code: "D1", definition:, pointer: child_pointer, id:, message: "未知のキー #{name}", candidates: known.keys)
      end
      message = schema[:rule]&.call(value)
      problems << Problem.new(code: "D1", definition:, pointer:, id:, message:) if message
    end
  end
end
