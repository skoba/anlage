module Opt
  # フォームの保存可否（skoba/anlage#36、壇上防御）。登録時に一度だけ判定して
  # web_template["form_capability"] に保存する:
  #   saveable      CompositionBuilder が全 field を組める
  #   preview_only  builder が扱えない形（SECTION 配下の ENTRY・INSTRUCTION・多段の埋め込み
  #                 CLUSTER 等）。フォームは閲覧専用にし、理由を明示する（保存経路の課題は #30）
  # 判定は builder のドライラン（input_kind ごとの作例値で build を試みる）で行い、
  # 判定規則を builder と二重に持たない。
  class FormCapability
    SAMPLE = {
      "number" => "1", "date" => "2026-01-01", "time" => "00:00", "datetime" => "2026-01-01",
      "coded_free" => "x", "coded_manual" => "x", "text" => "x"
    }.freeze

    def self.call(web_template)
      new(web_template).call
    end

    def initialize(web_template)
      @web_template = web_template
    end

    def call
      template = Template.new(template_id: @web_template["template_id"], web_template: @web_template)
      Opt::CompositionBuilder.new(template, sample_values(template)).build
      { "form_capability" => "saveable", "form_capability_reason" => nil }
    rescue Opt::CompositionBuilder::UnsupportedShape => e
      { "form_capability" => "preview_only", "form_capability_reason" => e.message }
    end

    private

    def sample_values(template)
      template.fields.each_with_object({}) do |field, values|
        name = field["name"]
        values[name] = field["input_kind"] == "select" ? Array(field["code_list"]).first : SAMPLE.fetch(field["input_kind"], "x")
        values["#{name}__code"] = "x" if field["input_kind"] == "coded_manual"
        values["#{name}__units"] = "x" if field["input_kind"] == "number"
      end
    end
  end
end
