# デモ用の身長OPTを登録して返す。
module HeightSeed
  module_function

  def template
    existing = Template.find_by(template_id: "bmi_calculation")
    existing || Template.build_from_opt_xml(
      Rails.root.join("spec/fixtures/opt/bmi_calculation.opt").read
    ).tap(&:save!)
  end
end
