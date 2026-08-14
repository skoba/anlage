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

    def self.call(template, json)
      new(template, json).call
    end

    def initialize(template, json)
      @template = template
      @json = json
    end

    def call
      composition = JSON.parse(@json)
      raise InvalidComposition, "not a COMPOSITION" unless composition["_type"] == "COMPOSITION"

      values = {}
      @template.entries.each do |entry|
        entry_node = (composition["content"] || []).find { |c| c["archetype_node_id"] == entry["archetype_id"] }
        next unless entry_node

        items = items_for(entry, entry_node)
        (entry["fields"] || []).each do |field|
          element = items&.find { |i| i["archetype_node_id"] == field["node_id"] }
          values[field["name"]] = extract_value(field, element["value"]) if element
        end
      end
      values
    rescue JSON::ParserError, NoMethodError, TypeError => e
      raise InvalidComposition, "not a valid composition for this template: #{e.message}"
    end

    private

    def items_for(entry, entry_node)
      data = entry_node["data"] || {}
      if entry["rm_type"] == "OBSERVATION"
        data.dig("events", 0, "data", "items")
      else
        data["items"]
      end
    end

    def extract_value(field, dv)
      return nil unless dv

      case field["rm_type"]
      when "DV_CODED_TEXT"
        dv.dig("defining_code", "code_string")
      when "DV_QUANTITY", "DV_COUNT"
        dv["magnitude"].to_s
      else
        dv["value"].to_s
      end
    end
  end
end
