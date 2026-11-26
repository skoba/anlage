module PatientsHelper
  # 記録日（context/start_time）を日本時間の日付で出す。初期データの記録日と同じ時間帯（skoba/anlage#182、計画書 8.2）
  def recorded_date(time)
    time ? time.in_time_zone(Demo::SampleCompositions::RECORDED_ZONE).strftime("%Y-%m-%d") : "—"
  end

  # 行の文字のテンプレートの ID。無い記録は COMPOSITION の archetype_node_id
  def record_template_label(record)
    record.template_id.presence || record.archetype_node_id
  end
end
