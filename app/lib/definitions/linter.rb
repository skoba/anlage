module Definitions
  # 定義の組（1 つのディレクトリ）の検査（docs/design/definition-layer-plan.md 2.2、skoba/anlage#257）。
  # 知識源は登録済みのテンプレート（Template.active）だけ。クエリビルダーのリンタ（QueryBuilder::Linter）と同じ考え方。
  # 組の置き方と書式は docs/reports/definitions-log.md R1。D9（流れ）は D-7 の段で足す
  class Linter
    BUNDLE = "bundle.yml".freeze
    QUANTITY_TYPES = %w[DV_QUANTITY DV_COUNT].freeze
    PROBLEM_ARCHETYPE = "openEHR-EHR-EVALUATION.problem_diagnosis.v1".freeze
    Definition = Data.define(:kind, :id, :path, :data)
    Report = Data.define(:problems) do
      def ok? = problems.none?(&:error?)
      def errors = problems.select(&:error?)
    end

    def self.call(dir, templates: Template.active)
      new(dir, templates).call
    end

    def initialize(dir, templates)
      @root = Pathname(dir)
      @templates = templates.to_a.index_by(&:template_id)
      @problems = []
    end

    def call
      bundle = load("bundle", @root.join(BUNDLE))
      return Report.new(problems: @problems) unless bundle

      screens = load_listed(bundle, "screens", "screen")
      logics = load_listed(bundle, "logic", "logic")
      check_bundle(bundle)
      check_ids(screens + logics)
      screens.each { check_screen(_1, screens) }
      check_reachable(bundle, screens)
      logics.each { check_logic(_1) }
      Report.new(problems: @problems)
    end

    private

    # 読めて D1 を通った定義だけを返す（通らないものは、ほかの検査をしない）
    def load(kind, path)
      relative = path.relative_path_from(@root).to_s
      result = Loader.read(path, root: @root)
      @problems.concat(result.problems)
      return unless result.data

      schema = Schema.check(kind, result.data, definition: relative)
      @problems.concat(schema)
      Definition.new(kind:, id: result.data[kind], path: relative, data: result.data) if schema.empty?
    end

    def load_listed(bundle, key, kind)
      Array(bundle.data[key]).each_with_index.filter_map do |id, index|
        path = @root.join(key, "#{id}.yml")
        next problem("D3", bundle, "/#{key}/#{index}", "定義のファイル #{key}/#{id}.yml が無い") unless path.file?

        definition = load(kind, path)
        next problem("D3", definition, "/#{kind}", "#{kind} は #{id} でなければならない（ファイル名と同じ）") if definition && definition.id != id

        definition
      end
    end

    def check_bundle(bundle)
      Array(bundle.data["templates"]).each_with_index do |ref, index|
        template_or_problem(bundle, "/templates/#{index}/template_id", ref["template_id"])
      end
    end

    # D2: id は組の中で一意（画面・ロジックの id、section・ボタン・rule の id）
    def check_ids(definitions)
      seen = {}
      definitions.each do |definition|
        ids_of(definition).each do |pointer, id|
          if (first = seen[id])
            problem("D2", definition, pointer, "id #{id} が重なる（先に #{first} で使っている）", id:)
          else
            seen[id] = "#{definition.path}#{pointer}"
          end
        end
      end
    end

    def ids_of(definition)
      data = definition.data
      top = [ [ "/#{definition.kind}", definition.id ] ]
      return top + data["rules"].each_with_index.map { |rule, index| [ "/rules/#{index}/id", rule["id"] ] } if definition.kind == "logic"

      top + data["sections"].each_with_index.flat_map do |section, index|
        [ [ "/sections/#{index}/id", section["id"] ] ] +
          Array(section["items"]).each_with_index.map { |item, item_index| [ "/sections/#{index}/items/#{item_index}/id", item["id"] ] }
      end
    end

    def check_screen(screen, screens)
      screen.data["sections"].each_with_index do |section, index|
        base = "/sections/#{index}"
        id = section["id"]
        check_from(screen, section, base, id)
        Array(section["items"]).each_with_index do |item, item_index|
          check_open(screen, item["open"], "#{base}/items/#{item_index}/open", item["id"], screens)
        end
      end
    end

    # D3（参照が実在する）と D4（部品と項目の型）
    def check_from(screen, section, base, id)
      from = section["from"] || {}
      template = from["template"] && template_or_problem(screen, "#{base}/from/template", from["template"], id:)
      fields = []
      fields << [ "#{base}/from/field", from["field"] ] if from["field"]
      Array(from["fields"]).each_with_index { |name, index| fields << [ "#{base}/from/fields/#{index}", name ] }
      found = template ? fields.filter_map { |pointer, name| field_or_problem(screen, template, pointer, name, id) } : []
      series_key = template && section["series_key"] && field_or_problem(screen, template, "#{base}/series_key", section["series_key"], id)
      check_archetype(screen, section, from, base, id) if from["archetype"]
      check_types(screen, section, found, series_key, base, id)
    end

    def check_archetype(screen, section, from, base, id)
      archetype = from["archetype"]
      archetype_fields = @templates.values.flat_map(&:fields).select { _1["archetype_id"] == archetype }
      if archetype_fields.empty?
        known = @templates.values.flat_map { |template| template.entries.map { _1["archetype_id"] } }.uniq
        return problem("D3", screen, "#{base}/from/archetype", "アーキタイプ #{archetype} は、登録済みのテンプレートに無い", id:, candidates: known)
      end
      problem("D4", screen, "#{base}/from/archetype", "problem_list は #{PROBLEM_ARCHETYPE} だけを受ける", id:) if section["component"] == "problem_list" && archetype != PROBLEM_ARCHETYPE
      node_ids = archetype_fields.map { _1["node_id"] }.uniq
      Array(section["columns"]).each_with_index do |code, index|
        next if node_ids.include?(code)

        problem("D3", screen, "#{base}/columns/#{index}", "at-code #{code} は #{archetype} の項目に無い", id:,
                candidates: archetype_fields.uniq { _1["node_id"] }.map { "#{_1['node_id']}（#{_1['label']}）" })
      end
    end

    def check_types(screen, section, fields, series_key, base, id)
      case section["component"]
      when "time_series", "lab_table"
        fields.each do |pointer, field|
          next if QUANTITY_TYPES.include?(field["rm_type"])

          problem("D4", screen, pointer, "#{section['component']} の項目 #{field['name']} は #{field['rm_type']}。DV_QUANTITY か DV_COUNT でなければならない", id:)
        end
        if section["component"] == "lab_table" && series_key && series_key[1]["rm_type"] != "DV_TEXT"
          problem("D4", screen, "#{base}/series_key", "lab_table の series_key は DV_TEXT の項目でなければならない", id:)
        end
      when "problem_list"
        problem("D4", screen, "#{base}/from", "problem_list は from.archetype で #{PROBLEM_ARCHETYPE} を指す", id:) unless section.dig("from", "archetype")
      end
    end

    # D5: 遷移先の画面・帳票が実在する
    def check_open(screen, open, pointer, id, screens)
      names = screens.map(&:id)
      if open["form"] && !@templates.key?(open["form"])
        problem("D5", screen, "#{pointer}/form", "帳票 #{open['form']} は登録されていない", id:, candidates: @templates.keys)
      end
      [ [ "#{pointer}/screen", open["screen"] ], [ "#{pointer}/then/screen", open.dig("then", "screen") ] ].each do |at, name|
        problem("D5", screen, at, "画面 #{name} は組に無い", id:, candidates: names) if name && !names.include?(name)
      end
    end

    # D6: start とボタン（open.screen、then.screen）から、すべての画面にたどり着ける
    def check_reachable(bundle, screens)
      start = bundle.data.dig("start", "screen")
      return if screens.empty?
      return problem("D5", bundle, "/start/screen", "画面 #{start} は組に無い", candidates: screens.map(&:id)) unless screens.any? { _1.id == start }

      edges = screens.to_h { |screen| [ screen.id, targets(screen) ] }
      reached = Set[start]
      queue = [ start ]
      while (current = queue.shift)
        (edges[current] || []).each { |target| queue << target if reached.add?(target) }
      end
      screens.reject { reached.include?(_1.id) }.each do |screen|
        problem("D6", screen, "", "画面 #{screen.id} には、start からもボタンからもたどり着けない")
      end
    end

    def targets(screen)
      screen.data["sections"].flat_map { Array(_1["items"]) }.flat_map { [ _1.dig("open", "screen"), _1.dig("open", "then", "screen") ] }.compact
    end

    # D7（対象・入力・式）と D8（出どころとレビュー者）
    def check_logic(logic)
      template = template_or_problem(logic, "/template", logic.data["template"])
      if template
        logic.data["rules"].each_with_index { |rule, index| check_rule(logic, template, rule, "/rules/#{index}") }
      end
      missing = %w[source reviewed_by].reject { logic.data[_1].present? }
      return if missing.empty?

      problem("D8", logic, "", "#{missing.join('・')} が無い。案として扱い、保存には効かない", severity: :draft)
    end

    def check_rule(logic, template, rule, base)
      id = rule["id"]
      names = template.fields.map { _1["name"] }
      unless names.include?(rule["target"])
        problem("D7", logic, "#{base}/target", "対象 #{rule['target']} は #{template.template_id} の帳票に無い", id:, candidates: field_candidates(template))
      end
      inputs = Array(rule["inputs"])
      inputs.each_with_index do |input, index|
        next if names.include?(input)

        problem("D7", logic, "#{base}/inputs/#{index}", "入力 #{input} は #{template.template_id} の帳票に無い", id:, candidates: field_candidates(template))
      end
      check_expression(logic, rule["formula"], "#{base}/formula", inputs, id) if rule["formula"]
      Array(rule["cases"]).each_with_index do |entry, index|
        check_expression(logic, entry["when"], "#{base}/cases/#{index}/when", inputs, id) if entry["when"]
      end
    end

    # 式の文法は Opt::Formula が正（同じ文法を 2 つ持たない）。識別子をすべて 1.0 にして評価し、読めるかを見る。
    # そのあと、識別子が入力に含まれるかを見る
    def check_expression(logic, expression, pointer, inputs, id)
      identifiers = expression.scan(Opt::Formula::TOKEN).filter_map { |_number, ident, _op| ident }.uniq - [ "round" ]
      Opt::Formula.evaluate(expression, identifiers.index_with(1.0))
      (identifiers - inputs).each do |name|
        problem("D7", logic, pointer, "式に、入力に無い識別子 #{name} がある", id:, candidates: inputs)
      end
    rescue Opt::Formula::Error => e
      problem("D7", logic, pointer, "式を読めない（#{e.message}）", id:)
    end

    def template_or_problem(definition, pointer, template_id, id: nil)
      @templates[template_id] ||
        problem("D3", definition, pointer, "テンプレート #{template_id} は登録されていない", id:, candidates: @templates.keys) && nil
    end

    def field_or_problem(definition, template, pointer, name, id)
      field = template.fields.find { _1["name"] == name }
      return [ pointer, field ] if field

      problem("D3", definition, pointer, "#{name.inspect} は #{template.template_id} に無い", id:, candidates: field_candidates(template))
      nil
    end

    def field_candidates(template) = template.fields.map { "#{_1['name']}（#{_1['label']}）" }

    def problem(code, definition, pointer, message, id: nil, candidates: [], severity: :error)
      @problems << Problem.new(code:, definition: definition.path, pointer:, id:, message:, candidates:, severity:)
      nil
    end
  end
end
