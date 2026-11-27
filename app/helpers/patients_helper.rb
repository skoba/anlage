module PatientsHelper
  # 記録日（context/start_time）を日本時間の日付で出す。初期データの記録日と同じ時間帯（skoba/anlage#182、計画書 8.2）
  def recorded_date(time)
    time ? time.in_time_zone(Demo::SampleCompositions::RECORDED_ZONE).strftime("%Y-%m-%d") : "—"
  end

  # 行の文字のテンプレートの ID。無い記録は COMPOSITION の archetype_node_id
  def record_template_label(record)
    record.template_id.presence || record.archetype_node_id
  end

  # 「この患者の記録を AQL で引く」の問い（R-20261127-9 の作業列 3）。EHR ID は query_parameters の $ehr_id で渡す
  PATIENT_RECORDS_AQL = "SELECT c/uid/value AS uid, c/archetype_details/template_id/value AS template, " \
                        "c/context/start_time/value AS recorded_at " \
                        "FROM EHR e[ehr_id/value=$ehr_id] CONTAINS COMPOSITION c".freeze

  # AQL 照会の画面を、問いと EHR ID を入れた状態で開く URL（openehr-rails 0.12.0 の GET /query?q=&query_parameters=）。
  # 開いただけでは実行しない
  def patient_records_aql_path(patient)
    openehr_rails.query_console_path(q: PATIENT_RECORDS_AQL, query_parameters: { ehr_id: patient.ehr_id }.to_json)
  end

  # 患者の画面の部品から、その記録の画面へ（原本があれば記録の画面、無ければ閲覧の画面。#182 と同じ）
  def chart_record_path(patient, record, originals)
    original = originals[record.uid]
    original ? composition_path(original) : record_patient_path(patient.ehr_id, uid: record.uid)
  end

  # プロブレムリストの列の見出し（テンプレートのラベル。最初の行のテンプレートから）
  def problem_list_labels(problem)
    template = Template.active.find_by!(template_id: problem.template_id)
    component = Charts::Rules.for(template).find { _1.kind == :problem_list }
    %w[diagnosis certainty onset].map { component.fields[_1]&.dig("label") }
  end
end
