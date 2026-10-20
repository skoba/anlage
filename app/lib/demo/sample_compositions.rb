module Demo
  # rake demo:reset のサンプルのカルテ記録（skoba/anlage#47 裁定 D 2026-10-12・裁定 2026-10-20）。
  # 壇上の入力が 1 件失敗しても第 3 幕が空にならないようにする。値は作例（臨床文書ではない）。
  #   - フォーム保存経路と同じ RmCompositionCommitter（値 → canonical → RM グラフ）で 4 件
  #   - ICD-11 コード付きの傷病名は、ProblemList の at0002 が coded_free（フォームは DV_TEXT で保存、
  #     Opt::CompositionBuilder）なので、フォーム経路の canonical の at0002 だけを DV_CODED_TEXT に
  #     差し替えて直接コミットする（OR 制約の他方＝代替制約の実演）
  #   - jp_referral はテンプレートを壇上で登録する（第 1 幕）ので、構造骨格 fixture を RM グラフにだけ
  #     直接コミットする（フォーム保存経路は #30 で未対応。#23 (4) 裁定 C と同じ経路）
  module SampleCompositions
    ICD11_MMS = "http://id.who.int/icd/release/11/mms".freeze
    TYPE_2_DIABETES = { "value" => "2型糖尿病", "code" => "5A11" }.freeze
    JP_REFERRAL_SKELETON = "spec/fixtures/compositions/jp_referral/skeleton.canonical.json".freeze

    FORM_VALUES = {
      "ProblemList" => [ { "problem_diagnosis_at0002" => "高血圧症", "problem_diagnosis_at0073" => "at0074" } ],
      "CardiologyEncounter" => [ { "blood_pressure_at0004" => "120", "blood_pressure_at0005" => "80" } ],
      "LabResultReport" => [ { "laboratory_test_result_at0005" => "血液検査", "laboratory_test_analyte_at0024" => "空腹時血糖",
                               "laboratory_test_analyte_at0001" => "98", "laboratory_test_analyte_at0001__units" => "mg/dL" } ],
      "bmi_calculation" => [ { "height" => "170", "body_weight" => "65", "body_mass_index" => "22.5", "body_mass_index_at0013" => "普通体重" } ]
    }.freeze

    module_function

    def load!
      FORM_VALUES.each do |template_id, value_sets|
        template = Template.active.find_by!(template_id: template_id)
        value_sets.each { |values| commit_via_form_path(template, values) }
      end
      commit_coded_problem_list
      OpenehrRails::Rm::CompositionCommitter.commit(jp_referral_skeleton, uid: SecureRandom.uuid, owner: nil)
    end

    def commit_via_form_path(template, values)
      commit = Opt::RmCompositionCommitter.call(template, values)
      template.compositions.create!(rm_composition: commit.canonical_hash, uid: commit.uid)
    end

    def commit_coded_problem_list
      template = Template.active.find_by!(template_id: "ProblemList")
      values = { "problem_diagnosis_at0002" => TYPE_2_DIABETES["value"], "problem_diagnosis_at0073" => "at0074" }
      canonical = JSON.parse(OpenEHR::Serializer::RMJSONSerializer.new(Opt::CompositionBuilder.new(template, values).build).serialize)
      canonical["content"].each do |entry|
        diagnosis = entry.dig("data", "items")&.find { _1["archetype_node_id"] == "at0002" }
        diagnosis["value"] = coded_diagnosis if diagnosis
      end

      uid = SecureRandom.uuid
      committable = canonical.deep_dup
      committable["content"].each { |entry| Opt::RmCompositionCommitter::NON_STRUCTURAL_ENTRY_KEYS.each { entry.delete(_1) } }
      OpenehrRails::Rm::CompositionCommitter.commit(committable, uid: uid, owner: nil)
      template.compositions.create!(rm_composition: canonical, uid: uid)
    end

    def jp_referral_skeleton
      JSON.parse(Rails.root.join(JP_REFERRAL_SKELETON).read).tap do |canonical|
        diagnosis = canonical.dig("content", 0, "items").find { _1["archetype_node_id"] == "openEHR-EHR-EVALUATION.problem_diagnosis.v1" }
                             .dig("data", "items").find { _1["archetype_node_id"] == "at0002" }
        diagnosis["value"] = coded_diagnosis
      end
    end

    def coded_diagnosis
      { "_type" => "DV_CODED_TEXT", "value" => TYPE_2_DIABETES["value"],
        "defining_code" => { "_type" => "CODE_PHRASE", "terminology_id" => { "_type" => "TERMINOLOGY_ID", "value" => ICD11_MMS },
                             "code_string" => TYPE_2_DIABETES["code"] } }
    end
  end
end
