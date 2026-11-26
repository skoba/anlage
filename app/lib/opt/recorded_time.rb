module Opt
  # 記録の原本（canonical の Hash）の、記録した時刻（skoba/anlage#171）。最初の OBSERVATION の最初の EVENT の time。
  # 修正の版は、この時刻を引き継ぐ（測った時刻は、値を直しても変わらない）。修正できるかの判定（CompositionEditability）も、
  # この時刻で組み直して比べる。OBSERVATION の無い記録は nil。
  # 時刻は原本の書き方（オフセット）のまま返す（Time.iso8601）。組み直すと同じ文字列になる。
  module RecordedTime
    module_function

    def of(canonical_hash)
      value = first_event_time(canonical_hash.fetch("content", []))
      value && Time.iso8601(value)
    rescue ArgumentError
      nil
    end

    def first_event_time(items)
      items.each do |item|
        next unless item.is_a?(Hash)

        found = item["_type"] == "SECTION" ? first_event_time(item.fetch("items", [])) : item.dig("data", "events", 0, "time", "value")
        return found if found
      end
      nil
    end
  end
end
