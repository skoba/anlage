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

      Result.new(cards: extract_cards(opt), report: {})
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
        "constraints" => {},
        "bindings" => [],
        "capture" => {},
        "reserved" => {},
        "provenance" => {}
      }
    end
  end
end
