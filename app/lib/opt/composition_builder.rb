module Opt
  # Builds a canonical OpenEHR::RM::Composition::Composition directly
  # from a Template's web_template (FieldExtractor output) and submitted
  # form values -- no code generation, no scaffolded model. Each field's
  # RM `path` (e.g. "/content[...]/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value")
  # is parsed to reconstruct the minimal wrapper chain it was extracted
  # from, mirroring OpenehrRails::Rm::RmObjectBuilder's construction
  # style (see docs/upstream-candidates.md #4 for why its private value
  # builders are duplicated here rather than reused).
  #
  # Known Phase 1 boundary: assumes a single, non-repeating event/branch
  # per entry and a flat ITEM_TREE of ELEMENTs (no nested CLUSTER, no
  # repeating events) -- this matches every shape FieldExtractor itself
  # flattens archetypes into today. An entry whose fields don't share one
  # wrapper chain raises UnsupportedShape rather than silently building
  # something RM-nonconformant.
  class CompositionBuilder
    class UnsupportedShape < StandardError; end

    ENTRY_CLASSES = {
      "OBSERVATION" => OpenEHR::RM::Composition::Content::Entry::Observation,
      "EVALUATION" => OpenEHR::RM::Composition::Content::Entry::Evaluation,
      "ADMIN_ENTRY" => OpenEHR::RM::Composition::Content::Entry::AdminEntry
    }.freeze

    def initialize(template, values)
      @template = template
      @values = values.stringify_keys
    end

    def build
      OpenEHR::RM::Composition::Composition.new(
        archetype_node_id: @template.web_template["template_id"],
        name: dv_text(@template.web_template["concept"] || @template.template_id),
        language: code_phrase(OpenehrRails.default_language, "ISO_639-1"),
        territory: code_phrase(OpenehrRails.default_territory, "ISO_3166-1"),
        category: dv_coded_text(*OpenehrRails.default_category, "openehr"),
        composer: OpenEHR::RM::Common::Generic::PartyIdentified.new(name: OpenehrRails.default_composer_name),
        content: @template.entries.map { |entry| build_entry(entry) }
      )
    end

    private

    def build_entry(entry)
      klass = ENTRY_CLASSES.fetch(entry["rm_type"]) do
        raise UnsupportedShape, "entry rm_type #{entry['rm_type']} is not supported yet"
      end

      klass.new(
        archetype_node_id: entry["archetype_id"],
        name: dv_text(entry["concept"]),
        language: code_phrase(OpenehrRails.default_language, "ISO_639-1"),
        encoding: code_phrase(OpenehrRails.default_encoding, "IANA_character-sets"),
        subject: OpenEHR::RM::Common::Generic::PartySelf.new(external_ref: nil),
        data: build_data(entry)
      )
    end

    def build_data(entry)
      fields = entry["fields"]
      raise UnsupportedShape, "entry #{entry['archetype_id']} has no fields" if fields.blank?

      chains = fields.map { |f| wrapper_chain(f["path"]) }.uniq
      unless chains.size == 1
        raise UnsupportedShape, "entry #{entry['archetype_id']} fields span more than one branch (#{chains.inspect})"
      end

      item_tree_seg, *outer_segs = chains.first.reverse
      item_tree = build_item_tree(item_tree_seg, entry, fields)

      case entry["rm_type"]
      when "OBSERVATION"
        wrap_in_history(outer_segs.reverse, item_tree)
      else
        raise UnsupportedShape, "unexpected wrapper depth for #{entry['rm_type']}" if outer_segs.any?

        item_tree
      end
    end

    # [[attr, node_id], ...] from outermost to innermost, excluding the
    # entry's own "content[...]" prefix, the trailing "value" leaf and
    # the ELEMENT's own "items[node_id]" segment (handled per-field).
    def wrapper_chain(path)
      segments = path.split("/").reject(&:empty?)
      segments.shift # content[...]
      segments.pop   # "value"
      segments.pop   # items[element_node_id] -- the element itself
      segments.map { |seg| seg.match(/\A(\w+)\[(.+)\]\z/).captures }
    end

    def build_item_tree(item_tree_seg, entry, fields)
      _attr, node_id = item_tree_seg
      OpenEHR::RM::DataStructures::ItemStructure::ItemTree.new(
        archetype_node_id: node_id,
        name: dv_text(entry["concept"]),
        items: fields.map { |field| build_element(field) }
      )
    end

    # outer_segs: [[HISTORY attr, node_id], [EVENT attr, node_id]], outermost first.
    def wrap_in_history(outer_segs, item_tree)
      raise UnsupportedShape, "OBSERVATION without a HISTORY/EVENT wrapper" unless outer_segs.size == 2

      (_, history_node_id), (_, event_node_id) = outer_segs

      event = OpenEHR::RM::DataStructures::History::PointEvent.new(
        archetype_node_id: event_node_id,
        name: dv_text("event"),
        time: dv_date_time(Time.current),
        data: item_tree
      )

      OpenEHR::RM::DataStructures::History::History.new(
        archetype_node_id: history_node_id,
        name: dv_text("history"),
        origin: dv_date_time(Time.current),
        events: [ event ]
      )
    end

    def build_element(field)
      OpenEHR::RM::DataStructures::ItemStructure::Representation::Element.new(
        archetype_node_id: field["node_id"],
        name: dv_text(field["label"]),
        value: build_value(field, @values.fetch(field["name"]))
      )
    end

    def build_value(field, raw_value)
      case field["rm_type"]
      when "DV_QUANTITY"
        OpenEHR::RM::DataTypes::Quantity::DvQuantity.new(magnitude: Float(raw_value), units: field["units"])
      when "DV_COUNT"
        OpenEHR::RM::DataTypes::Quantity::DvCount.new(magnitude: Integer(raw_value))
      when "DV_CODED_TEXT"
        dv_coded_text(field.dig("code_labels", raw_value) || raw_value, raw_value, field["terminology_id"] || "local")
      when "DV_BOOLEAN"
        OpenEHR::RM::DataTypes::Basic::DvBoolean.new(value: ActiveModel::Type::Boolean.new.cast(raw_value))
      when "DV_DATE"
        OpenEHR::RM::DataTypes::Quantity::DateTime::DvDate.new(value: Date.parse(raw_value).iso8601)
      when "DV_DATE_TIME"
        dv_date_time(Time.zone.parse(raw_value))
      else
        dv_text(raw_value.to_s)
      end
    end

    def dv_text(value)
      OpenEHR::RM::DataTypes::Text::DvText.new(value: value.to_s)
    end

    def dv_coded_text(value, code, terminology)
      OpenEHR::RM::DataTypes::Text::DvCodedText.new(value: value, defining_code: code_phrase(code, terminology))
    end

    def code_phrase(code, terminology)
      OpenEHR::RM::DataTypes::Text::CodePhrase.new(
        terminology_id: OpenEHR::RM::Support::Identification::TerminologyID.new(name: terminology),
        code_string: code
      )
    end

    def dv_date_time(time)
      OpenEHR::RM::DataTypes::Quantity::DateTime::DvDateTime.new(value: time.iso8601)
    end
  end
end
