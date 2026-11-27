module Opt
  # Reverse of CompositionBuilder: reads a canonical openEHR RM
  # Composition (JSON, this app's own storage format -- the gem has no
  # composition-*instance* XML parser, only OPT/archetype XML, so XML
  # composition drops aren't supported) back into a {field_name => value}
  # hash, using the same HISTORY/EVENT/ITEM_TREE shape CompositionBuilder
  # assumes. Used to display an already-filled-in form for a dropped
  # composition that matches a registered template.
  #
  # Walks the parsed JSON Hash directly rather than going through
  # OpenEHR::RM::CompositionFactory.create_from_json: that factory
  # dispatches per "_type" to a "<Type>Factory" class, but
  # OpenEHR::Serializer::RMJSONSerializer (a generic reflection walker)
  # also serializes derived ivars DvDateTime keeps internally (e.g.
  # "timezone"), and the gem has no TimezoneFactory to parse that back --
  # NameError. Since this app only ever needs to read compositions it
  # produced itself (a known shape), a direct Hash walk sidesteps that
  # gem-level round-trip gap entirely (see docs/upstream-candidates.md #5).
  class CompositionReader
    class InvalidComposition < StandardError; end

    # display: true のときは、DV_CODED_TEXT を記録の表示の文字（value）で返す（患者の画面、skoba/anlage#219）。
    # 数量は精度を作らない表示の文字（Opt::QuantityDisplay、skoba/anlage#250）。
    # 既定（false）はコードと magnitude の文字（修正の帳票に入れる値）
    def self.call(template, json, display: false)
      new(template, json, display:).call
    end

    def initialize(template, json, display: false)
      @template = template
      @json = json
      @display = display
    end

    def call
      composition = JSON.parse(@json)
      raise InvalidComposition, "not a COMPOSITION" unless composition["_type"] == "COMPOSITION"

      values = {}
      @template.entries.each do |entry|
        entry_node = content_entries(composition["content"]).find { |c| c["archetype_node_id"] == entry["archetype_id"] }
        next unless entry_node

        items = items_for(entry, entry_node)
        (entry["fields"] || []).each do |field|
          # 埋め込み CLUSTER 一段（#38／#39）: field の archetype_id が entry と異なるときは、
          # その archetype_node_id を持つ CLUSTER の items から探す
          scope = if field["archetype_id"] && field["archetype_id"] != entry["archetype_id"]
                    items&.find { |i| i["archetype_node_id"] == field["archetype_id"] }&.dig("items")
          else
                    items
          end
          element = scope&.find { |i| i["archetype_node_id"] == field["node_id"] }
          next unless element

          values[field["name"]] = extract_value(field, element["value"])
          # skoba/anlage#138: 数量の単位も読み戻す（builder の入力と同じ <name>__units）
          units = element.dig("value", "units") if field["rm_type"] == "DV_QUANTITY"
          values["#{field['name']}__units"] = units if units.present?
        end
      end
      values
    rescue JSON::ParserError, NoMethodError, TypeError => e
      raise InvalidComposition, "not a valid composition for this template: #{e.message}"
    end

    private

    # SECTION は items を辿って、配下の ENTRY を平らに並べる（skoba/anlage#80）
    def content_entries(content_items)
      (content_items || []).flat_map { |item| item["_type"] == "SECTION" ? content_entries(item["items"]) : [ item ] }
    end

    # data の要素と、protocol の要素（skoba/anlage#111）を合わせて返す
    def items_for(entry, entry_node)
      data = entry_node["data"] || {}
      data_items = entry["rm_type"] == "OBSERVATION" ? data.dig("events", 0, "data", "items") : data["items"]
      Array(data_items) + Array(entry_node.dig("protocol", "items"))
    end

    def extract_value(field, dv)
      return nil unless dv

      case field["rm_type"]
      when "DV_CODED_TEXT"
        # coded_free は DV_TEXT として保存される（#33 裁定 A）。保存されている値の型で読む（skoba/anlage#82）
        dv["_type"] == "DV_TEXT" || @display ? dv["value"].to_s : dv.dig("defining_code", "code_string")
      when "DV_QUANTITY", "DV_COUNT"
        # display: true は精度を作らない表示（skoba/anlage#250）。既定は修正の帳票に入れる magnitude の文字
        @display ? Opt::QuantityDisplay.format(dv["magnitude"], dv["precision"]) : dv["magnitude"].to_s
      else
        dv["value"].to_s
      end
    end
  end
end
