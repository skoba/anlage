module Definitions
  # 帳票の保存のあとに進む先（ボタンの open.then。docs/design/definition-registration-plan.md 6 節、skoba/anlage#294）。
  # 帳票の URL には、ボタンの印 via=<組の行の id>.<ボタンの id> だけを付ける。進む先は URL から取らず、組の行からボタンを引き直す
  # （外の URL へ飛ばされる道を作らない）。引けないときは nil（呼ぶ側は、いまと同じ記録の画面へ）
  module Via
    TOKEN = /\A(\d+)\.(.+)\z/
    # bundle: 組の行（DefinitionBundle）。then: ボタンの open.then（{ "screen" => … } か { "record" => "saved" }）
    Target = Data.define(:bundle, :then)

    module_function

    def token(row_id, button_id) = "#{row_id}.#{button_id}"

    # template_id: 保存した帳票。ボタンの open.form が同じ帳票で、then のあるときだけ引ける
    def resolve(token, template_id:)
      match = TOKEN.match(token.to_s) or return
      bundle = DefinitionBundle.find_by(id: match[1]) or return
      report = ActiveScreen.lint(bundle)
      return unless report.ok?

      button = report.screens.flat_map { _1.data["sections"] }.flat_map { Array(_1["items"]) }.find { _1["id"] == match[2] }
      open = button && button["open"]
      return unless open && open["form"] == template_id && open["then"]

      Target.new(bundle:, then: open["then"])
    end
  end
end
