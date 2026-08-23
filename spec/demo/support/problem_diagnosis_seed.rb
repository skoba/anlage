# 実パイプライン駆動（構築からRMグラフ投入までの詳細は
# Opt::RmCompositionCommitter を参照）。
# ProblemList.opt（openEHR-EHR-EVALUATION.problem_diagnosis.v1）のCompositionを
# Opt::CompositionBuilder経由で構築し、AQLが参照するRMグラフへ投入する。
module ProblemDiagnosisSeed
  module_function

  def template
    @template ||= begin
      existing = Template.find_by(template_id: "ProblemList")
      existing || Template.build_from_opt_xml(
        Rails.root.join("spec/fixtures/opt/ProblemList.opt").read
      ).tap(&:save!)
    end
  end

  # certainty_code: at0073のローカルcode_list実値（"at0074"=疑い/"at0075"=推定/"at0076"=確定）
  # recognized_at: at0003（臨床的に認識された日時）のISO8601文字列
  def seed!(certainty_code:, recognized_at: Time.current.iso8601)
    now = Time.current.iso8601
    values = {
      "problem_diagnosis_at0002" => "Demo diagnosis (#{certainty_code})",
      "problem_diagnosis_at0077" => now,
      "problem_diagnosis_at0003" => recognized_at,
      "problem_diagnosis_at0030" => now,
      "problem_diagnosis_at0073" => certainty_code
    }

    Opt::RmCompositionCommitter.call(template, values).composition
  end
end
