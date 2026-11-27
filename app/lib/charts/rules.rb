module Charts
  # 患者の画面（U1）の部品を、テンプレートの entry と field の RM の型とアーキタイプから決める
  # （skoba/anlage#219、docs/design/u1-patient-chart-plan.md 1.2・1.5、R-20261127-13）。
  #   - problem_diagnosis の entry → :problem_list（列は config/chart_defaults.yml の at-code）
  #   - INSTRUCTION を持つテンプレート → :orders（記録ごと）
  #   - 検査の分析の CLUSTER（分析名と分析結果） → :lab_table
  #   - OBSERVATION の数量の field（上に当たらないもの） → :time_series（field ごと）
  # 返す Component の fields は web_template の field（Hash）。ラベル・単位・選択肢の表示は field から引く
  module Rules
    Component = Struct.new(:kind, :template_id, :fields, keyword_init: true)
    DEFAULTS = Rails.root.join("config/chart_defaults.yml")
    QUANTITY_TYPES = %w[DV_QUANTITY DV_COUNT].freeze

    module_function

    def defaults
      @defaults ||= YAML.load_file(DEFAULTS)
    end

    def for(template)
      entries = template.entries
      components = entries.flat_map { |entry| entry_components(template, entry) }
      components.unshift(Component.new(kind: :orders, template_id: template.template_id, fields: {})) if entries.any? { _1["rm_type"] == "INSTRUCTION" }
      components
    end

    def entry_components(template, entry)
      fields = entry["fields"] || []
      problem = defaults.fetch("problem_list")
      if entry["archetype_id"] == problem["archetype_id"]
        return [ component(:problem_list, template, by_node(fields, entry["archetype_id"], problem["columns"])) ]
      end
      return [] unless entry["rm_type"] == "OBSERVATION"

      lab = defaults.fetch("lab_table")
      lab_fields = by_node(fields, lab["archetype_id"], "name" => lab["name"], "value" => lab["value"])
      lab_components = lab_fields.size == 2 ? [ component(:lab_table, template, lab_fields) ] : []
      series = fields.select { QUANTITY_TYPES.include?(_1["rm_type"]) && _1["archetype_id"] != lab["archetype_id"] }
                     .map { component(:time_series, template, "value" => _1) }
      lab_components + series
    end

    # 列の名前 → field（その archetype の at-code）。テンプレートに無い列は入れない
    def by_node(fields, archetype_id, columns)
      columns.filter_map do |key, node_id|
        field = fields.find { _1["archetype_id"] == archetype_id && _1["node_id"] == node_id }
        [ key, field ] if field
      end.to_h
    end

    def component(kind, template, fields)
      Component.new(kind:, template_id: template.template_id, fields:)
    end
  end
end
