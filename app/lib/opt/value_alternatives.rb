module Opt
  # ELEMENT の value 属性が持つ代替 RM 型の一覧を、field の path（FieldExtractor と
  # 同じ書式: 属性名 + `[archetype_id]` または `[node_id]`、末尾 `/value`）をキーに返す。
  #
  # gem の FieldExtractor は代替のうち C_CODE_REFERENCE を持つものを主型に選ぶだけで、
  # 代替の存在を field に載せない（skoba/anlage#33。gem 側の還流候補は
  # docs/upstream-candidates.md 19 項）。走査規則は PathcardExtractor#walk と同じ。
  class ValueAlternatives
    def self.call(opt)
      new(opt).call
    end

    def initialize(opt)
      @opt = opt
    end

    def call
      content = (@opt.definition.attributes || []).find { |a| a.rm_attribute_name == "content" }
      return {} unless content

      alternatives = {}
      (content.children || []).each do |root|
        archetype_id = archetype_id_of(root)
        next unless archetype_id

        walk(root, "/content[#{archetype_id}]", alternatives)
      end
      alternatives
    end

    private

    def walk(node, path, alternatives)
      return unless node.respond_to?(:attributes) && node.attributes

      node.attributes.each do |attribute|
        child_path = "#{path}/#{attribute.rm_attribute_name}"
        (attribute.children || []).each do |child|
          next unless child.respond_to?(:rm_type_name)

          predicate = archetype_id_of(child) || (child.node_id if child.respond_to?(:node_id))
          node_path = predicate ? "#{child_path}[#{predicate}]" : child_path

          if child.rm_type_name == "ELEMENT"
            alternatives["#{node_path}/value"] = value_alternatives(child)
          else
            walk(child, node_path, alternatives)
          end
        end
      end
    end

    def value_alternatives(element)
      value = (element.attributes || []).find { |a| a.rm_attribute_name == "value" }
      (value&.children || []).map(&:rm_type_name)
    end

    def archetype_id_of(node)
      node.archetype_id.value if node.respond_to?(:archetype_id) && node.archetype_id
    end
  end
end
