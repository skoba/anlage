module Opt
  # ELEMENT ごとの Anlage 側制約を field の path（FieldExtractor と同じ書式）をキーに返す:
  #   "alternatives"    value 属性の代替 RM 型（OPT 出現順、skoba/anlage#33）
  #   "min_occurrences" 要素の occurrences 下限（skoba/anlage#34。gem の required は
  #                     「entry が必須 かつ 要素が必須」なので 0..1 の entry 配下では常に false）
  #   "archetype_id"    要素が属する直近の C_ARCHETYPE_ROOT（skoba/anlage#38）
  #   "root_path"       そのルートの path（archetype_id 述語）
  #   "gem_path"        gem の FieldExtractor が書く path（埋め込みルートを items[at0000] で書く、
  #                     #29 と同型）。Template.build_web_template が field を訂正するための対応表
  #   "units_list"      DV_QUANTITY 代替の units 一覧（OPT 出現順、skoba/anlage#37）
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

        path = "/content[#{archetype_id}]"
        walk(root, path, path, archetype_id, path, constraints)
      end
      constraints
    end

    # gem の path（items[at0000]）→ 訂正後の path。同じ gem path に複数の要素が写る場合
    # （同一アーキタイプの複数埋め込み）は文書順の配列。
    def self.by_gem_path(constraints)
      constraints.each_with_object(Hash.new { |h, k| h[k] = [] }) { |(path, c), index| index[c.fetch("gem_path")] << path }
    end

    private

    def walk(node, path, gem_path, archetype_id, root_path, constraints)
      return unless node.respond_to?(:attributes) && node.attributes

      node.attributes.each do |attribute|
        child_path = "#{path}/#{attribute.rm_attribute_name}"
        child_gem_path = "#{gem_path}/#{attribute.rm_attribute_name}"
        (attribute.children || []).each do |child|
          next unless child.respond_to?(:rm_type_name)

          child_archetype_id = archetype_id_of(child)
          node_id = child.node_id if child.respond_to?(:node_id)
          predicate = child_archetype_id || node_id
          node_path = predicate ? "#{child_path}[#{predicate}]" : child_path
          node_gem_path = node_id ? "#{child_gem_path}[#{node_id}]" : child_gem_path

          if child.rm_type_name == "ELEMENT"
            constraints["#{node_path}/value"] = {
              "alternatives" => value_alternatives(child),
              "min_occurrences" => min_occurrences(child),
              "archetype_id" => archetype_id,
              "root_path" => root_path,
              "gem_path" => "#{node_gem_path}/value",
              "units_list" => units_list(child)
            }
          else
            walk(child, node_path, node_gem_path, child_archetype_id || archetype_id, child_archetype_id ? node_path : root_path, constraints)
          end
        end
      end
    end

    def units_list(element)
      value = (element.attributes || []).find { |a| a.rm_attribute_name == "value" }
      quantity = (value&.children || []).find { |c| c.rm_type_name == "DV_QUANTITY" && c.respond_to?(:list) }
      Array(quantity&.list).map { |item| item.units }.compact.uniq
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
