module Demo
  # rake demo:reset のサンプルのカルテ記録（skoba/anlage#144、R-20261125-9 で承認した docs/design/sample-data-plan.md）。
  # 架空の患者 6 人（DEMO-01〜06）の EHR を作り、sample_records.yml の 65 件を入れる。値は合成で、臨床文書ではない。
  # 壇上の入力が 1 件失敗しても第 3 幕が空にならないようにする（skoba/anlage#47 裁定 D 2026-10-12）。
  #   - 帳票のある記録は、帳票の検査（Opt::FormValidator）を通してから、フォーム保存経路と同じ RmCompositionCommitter で入れる。
  #     記録日は 09:00（日本時間）として、イベント時刻と context/start_time に入れる
  #   - icd11 のある傷病名は、canonical の at0002 だけを DV_CODED_TEXT に差し替えて入れる（ProblemList の at0002 は
  #     coded_free で、フォームは DV_TEXT で保存する。OR 制約の他方＝代替制約の実演）
  #   - jp_referral はテンプレートを壇上で登録する（第 1 幕）ので、構造骨格 fixture の複製の値を差し替えて、
  #     RM グラフにだけ入れる（#23 (4) 裁定 C と同じ経路）。fixture のファイルは変えない
  module SampleCompositions
    RECORDS = Rails.root.join("app/lib/demo/sample_records.yml")
    ICD11_MMS = "http://id.who.int/icd/release/11/mms".freeze
    ICD11_TITLES = { "5A11" => "2型糖尿病" }.freeze
    JP_REFERRAL_SKELETON = "spec/fixtures/compositions/jp_referral/skeleton.canonical.json".freeze
    JP_REFERRAL_OPT = "spec/fixtures/opt/jp_referral.opt".freeze
    PROBLEM_DIAGNOSIS = "openEHR-EHR-EVALUATION.problem_diagnosis.v1".freeze
    ORGANISATION = "openEHR-EHR-CLUSTER.organisation.v1".freeze
    RECORDED_ZONE = "Asia/Tokyo".freeze
    RECORDED_HOUR = "09:00".freeze

    # sample_records.yml の項目の名前 → 帳票の入力欄の名前（Template#fields の name）
    FIELDS = {
      "ProblemList" => { "diagnosis" => "problem_diagnosis_at0002", "onset" => "problem_diagnosis_at0077",
                         "certainty" => "problem_diagnosis_at0073" },
      "CardiologyEncounter" => { "systolic" => "blood_pressure_at0004", "diastolic" => "blood_pressure_at0005" },
      "patient_blood_pressure.v1" => { "systolic" => "blood_pressure_systolic", "diastolic" => "blood_pressure_diastolic",
                                       "pulse" => "heart_rate_pulse" },
      "LabResultReport" => { "test" => "laboratory_test_result_at0005", "analyte" => "laboratory_test_analyte_at0024",
                             "result" => "laboratory_test_analyte_at0001", "units" => "laboratory_test_analyte_at0001__units" },
      "bmi_calculation" => { "height" => "height", "weight" => "body_weight", "bmi" => "body_mass_index",
                             "judgement" => "body_mass_index_at0013" }
    }.freeze
    DEFAULTS = { "LabResultReport" => { "test" => "血液検査" } }.freeze
    NOT_VALUES = %w[row date template icd11].freeze

    class InvalidRecord < StandardError; end

    module_function

    def load!
      YAML.load_file(RECORDS, permitted_classes: [ Date ]).each do |subject_id, records|
        ehr = OpenehrRails::Rm::Ehr.create!(ehr_id: SecureRandom.uuid, subject_id: subject_id,
                                            subject_namespace: PatientsController::SUBJECT_NAMESPACE)
        records.each { |record| load_record(ehr, record) }
      end
    end

    def load_record(ehr, record)
      recorded_at = Time.find_zone!(RECORDED_ZONE).parse("#{record.fetch('date')} #{RECORDED_HOUR}")
      return commit_referral(ehr, record, recorded_at) if record.fetch("template") == "jp_referral"

      template = Template.active.find_by!(template_id: record.fetch("template"))
      values = form_values(record)
      result = Opt::FormValidator.call(template, values)
      raise InvalidRecord, "#{ehr.subject_id} ##{record["row"]}: #{result.errors}" unless result.valid?

      commit = Opt::RmCompositionCommitter.call(template, values, ehr: ehr, recorded_at: recorded_at) do |canonical|
        code_diagnosis(canonical["content"], record["icd11"]) if record["icd11"]
      end
      template.compositions.create!(rm_composition: commit.canonical_hash, uid: commit.uid)
    end

    def form_values(record)
      fields = FIELDS.fetch(record.fetch("template"))
      DEFAULTS.fetch(record["template"], {}).merge(record.except(*NOT_VALUES))
              .to_h { |key, value| [ fields.fetch(key), value.to_s ] }
    end

    def code_diagnosis(entries, code)
      entries.each do |entry|
        next code_diagnosis(entry.fetch("items", []), code) if entry["_type"] == "SECTION"

        diagnosis = entry.dig("data", "items")&.find { _1["archetype_node_id"] == "at0002" }
        diagnosis["value"] = coded_diagnosis(code) if diagnosis
      end
    end

    def coded_diagnosis(code)
      { "_type" => "DV_CODED_TEXT", "value" => ICD11_TITLES.fetch(code),
        "defining_code" => { "_type" => "CODE_PHRASE", "terminology_id" => { "_type" => "TERMINOLOGY_ID", "value" => ICD11_MMS },
                             "code_string" => code } }
    end

    # 紹介状: 骨格の複製の、傷病名・発症日時・紹介先の診療科を差し替える。確度は書かない（確度を書かない文書の形）
    def commit_referral(ehr, record, recorded_at)
      canonical = JSON.parse(Rails.root.join(JP_REFERRAL_SKELETON).read)
      section_items = canonical.dig("content", 0, "items")
      diagnosis_items = section_items.find { _1["archetype_node_id"] == PROBLEM_DIAGNOSIS }.dig("data", "items")
      diagnosis_items.find { _1["archetype_node_id"] == "at0002" }["value"] = { "_type" => "DV_TEXT", "value" => record.fetch("diagnosis") }
      code_diagnosis([ { "data" => { "items" => diagnosis_items } } ], record["icd11"]) if record["icd11"]
      diagnosis_items << onset_element(record["onset"]) if record["onset"]
      department(section_items)["value"] = { "_type" => "DV_TEXT", "value" => record.fetch("department") }

      OpenehrRails::Rm::CompositionCommitter.commit(canonical, uid: SecureRandom.uuid, ehr: ehr, owner: nil,
                                                               context_start_time: recorded_at)
    end

    # 紹介先医療機関（protocol の 2 つめの organisation）の中の、診療科（入れ子の organisation）の名称 at0001
    def department(section_items)
      receiver = section_items.find { _1["_type"] == "INSTRUCTION" }.dig("protocol", "items")
                              .select { _1["archetype_node_id"] == ORGANISATION }.second
      receiver.fetch("items").find { _1["archetype_node_id"] == ORGANISATION }
              .fetch("items").find { _1["archetype_node_id"] == "at0001" }
    end

    # 発症日時の ELEMENT。名前は jp_referral.opt の用語から引く（帳票の入力欄の label と同じ）
    def onset_element(onset)
      label = Template.build_from_opt_xml(Rails.root.join(JP_REFERRAL_OPT).read).fields
                      .find { _1["name"] == "problem_diagnosis_at0077" }.fetch("label")
      { "_type" => "ELEMENT", "archetype_node_id" => "at0077", "name" => { "_type" => "DV_TEXT", "value" => label },
        "value" => { "_type" => "DV_DATE_TIME", "value" => onset } }
    end
  end
end
