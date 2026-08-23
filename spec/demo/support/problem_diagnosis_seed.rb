# デモ用のProblemList OPTを登録して返す。
module ProblemDiagnosisSeed
  module_function

  def template
    existing = Template.find_by(template_id: "ProblemList")
    existing || Template.build_from_opt_xml(
      Rails.root.join("spec/fixtures/opt/ProblemList.opt").read
    ).tap(&:save!)
  end
end
