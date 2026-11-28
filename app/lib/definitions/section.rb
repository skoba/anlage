module Definitions
  # 画面の定義の部品 1 つ（docs/design/definition-registration-plan.md 3 節、skoba/anlage#281・#283）。
  # partial は、患者の画面で使う部品の中身（app/views/patients/sections/）。
  # from: { auto: true } は、U1 の規則で全体から引いたものをそのまま出す。from にテンプレート・field を書いた部品は、それだけを出す
  Section = Data.define(:id, :component, :from, :data) do
    def self.from(data) = new(id: data["id"], component: data["component"], from: data["from"] || {}, data:)

    def auto? = from["auto"] == true

    def partial
      return "orders" if component == "records" && from["rm_type"] == "INSTRUCTION"

      component
    end

    def field_names = [ from["field"], *from["fields"] ].compact

    # template_id を持つもの（Charts::PatientChart の Problem・LabRow・Order、RM の Composition）を、from.template で絞る
    def select_by_template(items)
      return items if auto? || from["template"].nil?

      items.select { _1.template_id == from["template"] }
    end

    # 経過の系列を、from.template と from.field・from.fields で絞る
    def select_series(series)
      series = select_by_template(series)
      return series if auto? || field_names.empty?

      series.select { field_names.include?(_1.field_name) }
    end

    def items = Array(data["items"])
  end
end
