module Opt
  # ELEMENT ごとの Anlage 側制約を field の path（FieldExtractor と同じ書式）をキーに返す:
  #   "alternatives"    value 属性の代替 RM 型（OPT 出現順、skoba/anlage#33）
  #   "min_occurrences" 要素の occurrences 下限（skoba/anlage#34。gem の required は
  #                     「entry が必須 かつ 要素が必須」なので 0..1 の entry 配下では常に false）
  # 走査規則は PathcardExtractor#walk と同じ。
  class ElementConstraints
    def self.call(opt)
      new(opt).call
    end

    def initialize(opt)
      @opt = opt
    end

    def call
      content = (@opt.definition.attributes || []).find { |a| a.rm_attribute_name == "content" }
      return {} unless content

      constraints = {}
      (content.children || []).each do |root|
        archetype_id = archetype_id_of(root)
        next unless archetype_id

        walk(root, "/content[#{archetype_id}]", constraints)
      end
      constraints
    end

    private

    def walk(node, path, constraints)
      return unless node.respond_to?(:attributes) && node.attributes

      node.attributes.each do |attribute|
        child_path = "#{path}/#{attribute.rm_attribute_name}"
        (attribute.children || []).each do |child|
          next unless child.respond_to?(:rm_type_name)

          predicate = archetype_id_of(child) || (child.node_id if child.respond_to?(:node_id))
          node_path = predicate ? "#{child_path}[#{predicate}]" : child_path

          if child.rm_type_name == "ELEMENT"
            constraints["#{node_path}/value"] = {
              "alternatives" => value_alternatives(child),
              "min_occurrences" => min_occurrences(child)
            }
          else
            walk(child, node_path, constraints)
          end
        end
      end
    end

    def value_alternatives(element)
      value = (element.attributes || []).find { |a| a.rm_attribute_name == "value" }
      (value&.children || []).map(&:rm_type_name)
    end

    def min_occurrences(element)
      occurrences = element.respond_to?(:occurrences) ? element.occurrences : nil
      occurrences&.lower.to_i
    end

    def archetype_id_of(node)
      node.archetype_id.value if node.respond_to?(:archetype_id) && node.archetype_id
    end
  end
end
