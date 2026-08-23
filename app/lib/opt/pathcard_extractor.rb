module Opt
  class PathcardExtractor
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
        "schema_version" => "1.0",
        "identity" => {
          "template_id" => @template.template_id,
          "archetype_id" => archetype_id,
          "path" => "#{path}/value",
          "at_code" => element.node_id
        },
        "semantics" => {},
        "constraints" => constraints_for(element),
        "bindings" => [],
        "capture" => {},
        "reserved" => {},
        "provenance" => {}
      }
    end

    def constraints_for(element)
      occurrences = element.occurrences
      value_attribute = (element.attributes || []).find do |attribute|
        attribute.rm_attribute_name == "value"
      end
      value_constraint = value_attribute&.children&.first

      {
        "occurrences" => {
          "lower" => occurrences&.lower,
          "upper" => occurrences&.upper
        },
        "value" => quantity_constraints(value_constraint, element.node_id)
      }
    end

    def quantity_constraints(value_constraint, at_code)
      quantity_class = OpenEHR::AM::OpenEHRProfile::DataTypes::Quantity::CDvQuantity
      return {} unless value_constraint.is_a?(quantity_class)

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
