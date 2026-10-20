module Opt
  # config/form_behaviors.yml の帳票の振る舞いをサーバ側で適用する（skoba/anlage#47 変更 4）。
  # CompositionsController#create が FormValidator の前に通す。builder は変えない（値は values に
  # 入って従来経路で保存される）。サーバが権威:
  #   - editable: false の target は inputs が揃えば常に再計算値で上書きする
  #   - editable: true の target は空欄のときだけ埋め、<target>__edited が立っていれば埋めない（裁定 C）
  module FormBehaviors
    CONFIG_PATH = Rails.root.join("config/form_behaviors.yml")
    EDITED_SUFFIX = "__edited".freeze

    module_function

    def rules_for(template_id)
      config.fetch(template_id, [])
    end

    def apply(template, values)
      rules = rules_for(template.template_id)
      return values if rules.empty?

      values = values.to_h.stringify_keys
      edited = rules.to_h { |rule| [ rule["target"], values.delete("#{rule['target']}#{EDITED_SUFFIX}").present? ] }
      rules.each do |rule|
        target = rule["target"]
        next if rule["editable"] && (values[target].present? || edited[target])

        inputs = numeric_inputs(rule, values) or next
        values[target] = evaluate(rule, inputs)
      end
      values
    end

    def config
      @config ||= YAML.safe_load_file(CONFIG_PATH).freeze
    end

    def numeric_inputs(rule, values)
      inputs = rule["inputs"].to_h { |name| [ name, Float(values[name].to_s, exception: false) ] }
      inputs unless inputs.values.any?(&:nil?)
    end

    def evaluate(rule, inputs)
      if rule["cases"]
        rule["cases"].find { |c| c.key?("else") || Formula.evaluate(c["when"], inputs) }
                     .then { |c| c.key?("else") ? c["else"] : c["value"] }
      else
        value = Formula.evaluate(rule["formula"], inputs)
        (rule["round"] ? value.round(rule["round"]) : value).to_s
      end
    end
  end
end
