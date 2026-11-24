module Opt
  # パース済みの OPT を前順（文書順）に辿り、ELEMENT ごとに、祖先の C_ARCHETYPE_ROOT（テンプレートのルート自身は除く）を
  # 外側から並べて返す（skoba/anlage#117）。各ルートは [archetype_id, ルートの path, その path の中での出現順]。
  # 出現順は Opt::RootTerms と同じ数え方（同じ前順）なので、RootTerms の配列の添字としてそのまま使える。
  #
  # 返す ELEMENT の path（"…/value"）は、openehr-rails 0.9.0 の FieldExtractor の field の path と同じ書式で、
  # 同じ path の ELEMENT の並びは field の instance_index（同じ path の中の文書順）と一致する
  # （jp_referral.opt の 26 項目で実測。docs/reports/rails-0.9.0-adoption-log.md R4）。同じ path に同じアーキタイプが
  # 並ぶとき（紹介元／紹介先の organisation）、どの項目がどのルートに属するかを、これで決める。
  # content の外（context など）の ELEMENT も含むので、呼ぶ側は path で引く。
  class ElementRoots
    ROOT = OpenEHR::AM::Archetype::ConstraintModel::CArchetypeRoot

    def self.call(opt)
      new(opt).call
    end

    def initialize(opt)
      @opt = opt
    end

    def call
      @occurrences = Hash.new(0)
      @elements = []
      walk(@opt.definition, [], top: true)
      @elements
    end

    private

    def walk(node, roots, top: false)
      if node.is_a?(ROOT) && !top
        roots += [ [ node.archetype_id.value, node.path, @occurrences[node.path] ] ]
        @occurrences[node.path] += 1
      end
      @elements << { "path" => "#{node.path}/value", "roots" => roots } if node.respond_to?(:rm_type_name) && node.rm_type_name == "ELEMENT"
      return unless node.respond_to?(:attributes)

      (node.attributes || []).each { |attribute| (attribute.children || []).each { |child| walk(child, roots) } }
    end
  end
end
