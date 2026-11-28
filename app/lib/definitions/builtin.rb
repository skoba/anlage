module Definitions
  # 組み込みの定義の組（config/definitions/builtin。docs/design/definition-registration-plan.md 3 節、skoba/anlage#281）。
  # 定義の組を動かしていないときの既定の画面。部品はどれも from: { auto: true } なので、テンプレートに依らず検査を通る
  module Builtin
    DIR = Rails.root.join("config/definitions/builtin")

    module_function

    def report = Linter.check(Files.read(DIR), templates: [])

    def patient_screen
      report.screens.find { _1.id == report.bundle.data.dig("start", "screen") }
    end
  end
end
