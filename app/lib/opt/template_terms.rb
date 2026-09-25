module Opt
  # OPT XML を再解析し、C_ARCHETYPE_ROOT ごと（＝同一アーキタイプの複数インスタンス別）の
  # term_definitions を返す。キーはルートの RM path（archetype_id 述語、FieldExtractor／
  # PathcardExtractor と同じ書式）、値はその path に現れるルートを文書順に並べた配列で、
  # 各要素は { at_code => { "text" => .., "description" => .. } }。
  #
  # gem のパース結果は各ルートの term_definitions を component_terminologies[archetype_id] に
  # 畳み込み、AD の改名（ルート名 at0000 も、要素名 at0002 等も）を後勝ちで失う
  # （skoba/openehr-ruby#58、docs/upstream-candidates.md 18 項）。skoba/anlage#31 の
  # container_labels と、2026-09-25 裁定の ELEMENT 改名の per-instance 化が共有する。
  # 撤去条件: openehr-ruby#58 が解消し CArchetypeRoot が per-root の term_definitions を持つ
  # 版へ bump した時点で gem 経路へ置換する。
  # 前提: OPT XML の文書順（xpath 結果順）と gem のパース結果の走査順が一致すること。
  class TemplateTerms
    def self.call(source_xml)
      new(source_xml).call
    end

    def initialize(source_xml)
      @source_xml = source_xml
    end

    def call
      document = Opt::SafeParser.safe_document(@source_xml)
      document.remove_namespaces!

      terms = Hash.new { |hash, key| hash[key] = [] }
      document.xpath("//*[@type='C_ARCHETYPE_ROOT']").each do |root|
        terms[root_rm_path(root)] << root_terms(root)
      end
      terms
    end

    private

    def root_terms(root)
      root.xpath("./term_definitions").each_with_object({}) do |definition, hash|
        code = definition["code"]
        next unless code

        hash[code] = {
          "text" => definition.at_xpath("./items[@id='text']")&.text,
          "description" => definition.at_xpath("./items[@id='description']")&.text
        }
      end
    end

    def root_rm_path(root)
      segments = []
      node = root
      while node && node.name != "definition"
        if node.name == "children"
          predicate = if node["type"] == "C_ARCHETYPE_ROOT"
                        node.at_xpath("./archetype_id/value")&.text
          else
                        node.at_xpath("./node_id")&.text
          end
          segments.unshift(predicate ? "[#{predicate}]" : "")
        elsif node.name == "attributes"
          segments.unshift("/#{node.at_xpath('./rm_attribute_name')&.text}")
        end
        node = node.parent
      end
      segments.join
    end
  end
end
