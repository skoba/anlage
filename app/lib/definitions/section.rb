module Definitions
  # 画面の定義の部品 1 つ（docs/design/definition-registration-plan.md 3 節、skoba/anlage#281）。
  # partial は、患者の画面で使う部品の中身（app/views/patients/sections/）
  Section = Data.define(:id, :component, :from, :data) do
    def self.from(data) = new(id: data["id"], component: data["component"], from: data["from"] || {}, data:)

    def auto? = from["auto"] == true

    def partial
      return "orders" if component == "records" && from["rm_type"] == "INSTRUCTION"

      component
    end
  end
end
