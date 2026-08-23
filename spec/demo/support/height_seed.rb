# 実パイプライン駆動（案A、docs/design/demo-queries-plan.md 2節）。
# 構築・canonical化・既知の回避策・RMグラフ投入は
# Opt::RmCompositionCommitter に集約する。
module HeightSeed
  module_function

  def template
    @template ||= begin
      existing = Template.find_by(template_id: "bmi_calculation")
      existing || Template.build_from_opt_xml(
        Rails.root.join("spec/fixtures/opt/bmi_calculation.opt").read
      ).tap(&:save!)
    end
  end

  def seed!(height_cm)
    values = {
      "height" => height_cm.to_s,
      "body_weight" => "70.0",
      "body_mass_index" => "21.6",
      "body_mass_index_at0013" => "normal"
    }

    Opt::RmCompositionCommitter.call(template, values).composition
  end
end
