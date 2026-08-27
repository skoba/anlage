require "digest"

module Opt
  class PathcardExtractor
    VERSION = "wp2-0.1.0"

    Result = Struct.new(:cards, :report, keyword_init: true)

    def self.call(template)
      new(template).call
    end

    def initialize(template)
      @template = template
    end

    def call
      opt = Opt::SafeParser.parse(@template.source_xml)
      @report = {}
      @opt = opt
      @code_bindings = extract_code_bindings(opt)

      Result.new(cards: extract_cards(opt), report: @report)
    end

    private

    def extract_cards(opt)
      content = (opt.definition.attributes || []).find do |attribute|
        attribute.rm_attribute_name == "content"
      end
      return [] unless content

      (content.children || []).flat_map do |root|
        archetype_id = archetype_id_of(root)
        next [] unless archetype_id

        walk(root, "/content[#{archetype_id}]", archetype_id)
      end
    end

    def walk(node, path, archetype_id)
      return [] unless node.respond_to?(:attributes) && node.attributes

      node.attributes.flat_map do |attribute|
        child_path = "#{path}/#{attribute.rm_attribute_name}"

        (attribute.children || []).flat_map do |child|
          next [] unless child.respond_to?(:rm_type_name)

          node_path = child_path.dup
          node_path << "[#{child.node_id}]" if child.respond_to?(:node_id) && child.node_id

          if child.rm_type_name == "ELEMENT"
            [ card_for(child, node_path, archetype_id) ]
          else
            walk(child, node_path, archetype_id_of(child) || archetype_id)
          end
        end
      end
    end

    def archetype_id_of(node)
      return unless node.respond_to?(:archetype_id) && node.archetype_id

      node.archetype_id.value
    end

    def card_for(element, path, archetype_id)
      {
        "schema_version" => "1.1",
        "identity" => {
          "template_id" => @template.template_id,
          "archetype_id" => archetype_id,
          "path" => "#{path}/value",
          "at_code" => element.node_id
        },
        "semantics" => semantics_for(archetype_id, element.node_id, element),
        "constraints" => constraints_for(element, archetype_id),
        "bindings" => bindings_for(element, archetype_id),
        "capture" => {},
        "reserved" => {},
        "provenance" => provenance
      }
    end

    def provenance
      checksum = if @template.respond_to?(:checksum)
                   @template.checksum
      else
                   Digest::SHA256.hexdigest(@template.source_xml)
      end

      {
        "source_template_id" => @template.template_id,
        "source_checksum" => checksum,
        "extracted_at" => Time.current.iso8601,
        "extractor_version" => VERSION
      }
    end

    def semantics_for(archetype_id, at_code, element)
      term = terminology_term(archetype_id, at_code)
      text = term&.items&.fetch("text", nil)
      description = term&.items&.fetch("description", nil)

      unless text
        (@report[:missing_labels] ||= []) << {
          "archetype_id" => archetype_id,
          "at_code" => at_code
        }
      end

      semantics = {
        "labels" => semantic_entries(text, archetype_id, at_code, "label"),
        "descriptions" => semantic_entries(description, archetype_id, at_code, "description"),
        "rm_type" => rm_type_for(element)
      }
      alternatives = value_attribute_children(element)
      if alternatives.size >= 2
        semantics["rm_type_alternatives"] = alternatives.map(&:rm_type_name)
      end
      semantics
    end

    def rm_type_for(element)
      primary_value_alternative(element)&.rm_type_name
    end

    def value_attribute_children(element)
      value_attribute = (element.attributes || []).find do |attribute|
        attribute.rm_attribute_name == "value"
      end
      value_attribute&.children || []
    end

    def primary_value_alternative(element)
      children = value_attribute_children(element)
      return children.first if children.size <= 1

      code_reference_class = OpenEHR::AM::OpenEHRProfile::DataTypes::Text::CCodeReference
      children.find do |child|
        defining_code_constraint(child).is_a?(code_reference_class)
      end || children.first
    end

    def terminology_term(archetype_id, at_code)
      terminology = @opt.component_terminologies[archetype_id]
      return unless terminology

      term = nil
      terminology.term_definitions.each_value do |terms|
        term = terms.find { |candidate| candidate.code == at_code }
        break if term
      end
      term
    end

    def semantic_entries(text, archetype_id, at_code, field)
      return [] unless text

      classification = classify_translation(text)
      if classification.fetch("untranslated_suspect")
        (@report[:untranslated_suspects] ||= []) << {
          "archetype_id" => archetype_id,
          "at_code" => at_code,
          "field" => field,
          "text" => text,
          "evidence" => classification.fetch("untranslated_evidence")
        }
      end

      [
        {
          "lang" => @opt.original_language.code_string,
          "text" => text
        }.merge(classification)
      ]
    end

    def classify_translation(text)
      fallback_match = text.match(/\A\*(.+?)(?:\(([a-z]{2}(?:-[a-z]{2})?)\))?\z/i)
      if fallback_match
        return {
          "untranslated_suspect" => true,
          "untranslated_evidence" => "fallback_marker",
          "source_lang" => fallback_match[2]
        }
      end

      if text.match?(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
        {
          "untranslated_suspect" => false,
          "untranslated_evidence" => nil,
          "source_lang" => nil
        }
      else
        {
          "untranslated_suspect" => true,
          "untranslated_evidence" => "no_ja_script",
          "source_lang" => nil
        }
      end
    end

    def constraints_for(element, archetype_id)
      occurrences = element.occurrences

      {
        "occurrences" => {
          "lower" => occurrences&.lower,
          "upper" => occurrences&.upper
        },
        "value" => value_constraints(primary_value_alternative(element), element.node_id, archetype_id)
      }
    end

    def value_constraints(value_constraint, at_code, archetype_id)
      value_constraint = defining_code_constraint(value_constraint)

      code_reference_class = OpenEHR::AM::OpenEHRProfile::DataTypes::Text::CCodeReference
      return {} if value_constraint.is_a?(code_reference_class)

      quantity_class = OpenEHR::AM::OpenEHRProfile::DataTypes::Quantity::CDvQuantity
      return quantity_constraints(value_constraint, at_code) if value_constraint.is_a?(quantity_class)

      code_phrase_class = OpenEHR::AM::OpenEHRProfile::DataTypes::Text::CCodePhrase
      return code_list_constraints(value_constraint, archetype_id) if value_constraint.is_a?(code_phrase_class)

      {}
    end

    def defining_code_constraint(value_constraint)
      return value_constraint unless value_constraint&.rm_type_name == "DV_CODED_TEXT"

      defining_code = (value_constraint.attributes || []).find do |attribute|
        attribute.rm_attribute_name == "defining_code"
      end
      defining_code&.children&.first
    end

    def bindings_for(element, archetype_id)
      code_reference_class = OpenEHR::AM::OpenEHRProfile::DataTypes::Text::CCodeReference
      value_constraint = defining_code_constraint(primary_value_alternative(element))
      bindings = []
      if value_constraint.is_a?(code_reference_class)
        bindings << {
          "kind" => "value_set_binding",
          "system_uri" => value_constraint.reference_set_uri,
          "code" => nil,
          "display" => nil
        }
      end

      bindings.concat(@code_bindings.fetch([ archetype_id, element.node_id ], []))
    end

    # code_bindingは、パース済みOPTの`component_terminologies`が持つ
    # `ArchetypeTerminology#term_bindings`（正規形
    # `{ terminology => { at_code => [CodePhrase] } }`）から読む。
    #
    # WP2当時この経路は存在せず、`source_xml`をNokogiriで再解析していた
    # （`docs/design/wp2-plan.md`の「経路2」）。上流`OPTParser`が
    # term_bindingsを落とす（`skoba/openehr-ruby#31`）ためスロットが空
    # だったのが理由で、現在はopenehr-rails 0.5.0の
    # `OpenehrRails::Opt::Parser#populate_term_bindings!`が同じ正規形へ
    # 投入している。両経路の出力が一致することは`docs/reports/fsh-log.md`
    # R4で実測確認済み（版数付きSNOMED表記
    # `[SNOMED-CT(2003)::271649006]`もgem側で正規化されず素通し）。
    #
    # これでAnlage側の迂回実装は無くなり、`#31`の迂回保有者は
    # openehr-rails側のnil-guard（`parser.rb`の`populate_term_bindings!`）
    # 1箇所に集約された。上流解消時はそちらの撤去だけで完了する。
    def extract_code_bindings(opt)
      bindings = Hash.new { |hash, key| hash[key] = [] }

      opt.component_terminologies.each do |archetype_id, terminology|
        next unless terminology.respond_to?(:term_bindings)

        (terminology.term_bindings || {}).each do |system_uri, codes|
          codes.each do |at_code, code_phrases|
            Array(code_phrases).each do |code_phrase|
              code = code_phrase.code_string
              next unless code

              bindings[[ archetype_id, at_code ]] << {
                "kind" => "code_binding",
                "system_uri" => system_uri,
                "code" => code,
                "display" => nil
              }
            end
          end
        end
      end

      bindings
    end

    def quantity_constraints(value_constraint, at_code)
      items = value_constraint.list || []
      (@report[:multi_unit_nodes] ||= []) << at_code if items.many?
      item = items.first

      {
        "property" => property_constraint(value_constraint.property),
        "units" => item&.units,
        "magnitude_range" => magnitude_range(item&.magnitude),
        "precision_range" => precision_range(item&.precision)
      }
    end

    def code_list_constraints(value_constraint, archetype_id)
      {
        "code_list" => (value_constraint.code_list || []).map do |code|
          term = terminology_term(archetype_id, code)
          { "code" => code, "label" => term&.items&.fetch("text", nil) }
        end
      }
    end

    def property_constraint(property)
      return unless property

      {
        "terminology" => property.terminology_id.value,
        "code" => property.code_string
      }
    end

    def magnitude_range(interval)
      return unless interval

      {
        "lower" => interval.lower,
        "upper" => interval.upper,
        "lower_included" => interval.lower_included?,
        "upper_included" => interval.upper_included?
      }
    end

    def precision_range(interval)
      return unless interval

      { "lower" => interval.lower, "upper" => interval.upper }
    end
  end
end
