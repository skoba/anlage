module Definitions
  # AI に渡す材料（docs/design/definition-layer-plan.md 2.4、R-20261127-21 の回答 3、skoba/anlage#259）。
  # 外の LLM に送られる前提で作る（コンテンツ防火壁。S4 の「外に送ってよいもの」〔R-20261127-14〕と同じ線）。
  # 項目は許したキーだけを写す（allowlist）。bindings・用語のコード・値集合・記録・患者・OPT のファイルは入れない
  module Context
    FIELD_KEYS = %w[name label rm_type archetype_id node_id units].freeze
    EXAMPLE = Rails.root.join("docs/definitions/example")
    COMPONENTS = {
      "problem_list" => { accepts: "from.archetype: openEHR-EHR-EVALUATION.problem_diagnosis.v1。columns: その at-code。全体から引くなら from: { auto: true }", shows: "プロブレムリスト（表）" },
      "time_series" => { accepts: "from.template と from.field か from.fields（DV_QUANTITY か DV_COUNT）。全体から引くなら from: { auto: true }", shows: "時系列（折れ線と表）" },
      "lab_table" => { accepts: "from.template、from.field（DV_QUANTITY か DV_COUNT の値）、series_key（DV_TEXT の名前の項目）。全体から引くなら from: { auto: true }", shows: "検査結果の時系列表" },
      "records" => { accepts: "from.template か from.rm_type（例 INSTRUCTION）。全体から引くなら from: { auto: true }（rm_type を足して絞れる）", shows: "記録の一覧" },
      "form" => { accepts: "from.template（登録済みのテンプレート）", shows: "帳票" },
      "table" => { accepts: "from.template と from.fields。全体から引くなら from: { auto: true }", shows: "表" },
      "buttons" => { accepts: "items: id・label・open（form か screen、任意で then）", shows: "ボタンの並び" }
    }.freeze
    # from の書き方の決まり（記録を引く部品は from が要る。書き忘れが黙って「全部を出す」にならない。R-20261128-7 の回答 4）
    FROM_RULE = "記録を引く部品（#{Schema::RECORD_COMPONENTS.join('・')}）は from が要る。" \
                "from: { auto: true } は、登録済みのテンプレート全体から U1 の規則で引く（rm_type のほかのキーと一緒に書けない）"
    CHECKS = {
      "D1" => "書式（スキーマ）に合う", "D2" => "id が組の中で重ならない", "D3" => "参照するテンプレート・field・archetype・at-code が実在する",
      "D4" => "部品と項目の型が合う", "D5" => "遷移先の画面・帳票が実在する", "D6" => "どこからもたどり着けない画面が無い",
      "D7" => "ロジックの対象・入力が帳票に実在し、式が読める", "D8" => "ロジックに出どころとレビュー者がある（無ければ案）"
    }.freeze

    module_function

    def call(templates: Template.active.order(:template_id))
      {
        templates: templates.map { template(_1) },
        components: Schema::COMPONENTS.map { |name| { name:, **COMPONENTS.fetch(name) } },
        from_rule: FROM_RULE,
        schemas: Schema::KINDS.keys.index_with { Schema.to_json_schema(_1) },
        checks: CHECKS,
        examples: examples
      }
    end

    def template(template)
      {
        template_id: template.template_id,
        entries: template.entries.map { |entry| { archetype_id: entry["archetype_id"], rm_type: entry["rm_type"], label: entry["label"] }.compact },
        fields: template.fields.map { |field| field.slice(*FIELD_KEYS).compact.symbolize_keys }
      }
    end

    def examples
      EXAMPLE.glob("**/*.yml").sort.to_h { [ _1.relative_path_from(EXAMPLE).to_s, _1.read ] }
    end
  end
end
