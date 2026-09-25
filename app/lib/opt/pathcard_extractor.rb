require "digest"

module Opt
  class PathcardExtractor
    VERSION = "wp2-0.2.0"

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
      @root_names = extract_root_names(@template.source_xml)
      @root_occurrences = Hash.new(0)

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

        path = "/content[#{archetype_id}]"
        walk(root, path, archetype_id, container_labels_for(path, archetype_id, []))
      end
    end

    # containers: 祖先 C_ARCHETYPE_ROOT のテンプレート名（container_labels entry）を
    # ルート→葉の順に積んだ配列。ELEMENT はルートになり得ないので葉には積まない。
    def walk(node, path, archetype_id, containers)
      return [] unless node.respond_to?(:attributes) && node.attributes

      node.attributes.flat_map do |attribute|
        child_path = "#{path}/#{attribute.rm_attribute_name}"

        (attribute.children || []).flat_map do |child|
          next [] unless child.respond_to?(:rm_type_name)

          node_path = child_path.dup
          # 埋め込み C_ARCHETYPE_ROOT は node_id が常に at0000 なので、content 直下
          # （extract_cards）と同じく archetype_id を述語にする（skoba/anlage#29）。
          predicate = archetype_id_of(child) || (child.node_id if child.respond_to?(:node_id))
          node_path << "[#{predicate}]" if predicate

          if child.rm_type_name == "ELEMENT"
            [ card_for(child, node_path, archetype_id, containers) ]
          else
            child_archetype_id = archetype_id_of(child)
            child_containers = child_archetype_id ? container_labels_for(node_path, child_archetype_id, containers) : containers
            walk(child, node_path, child_archetype_id || archetype_id, child_containers)
          end
        end
      end
    end

    def archetype_id_of(node)
      return unless node.respond_to?(:archetype_id) && node.archetype_id

      node.archetype_id.value
    end

    def card_for(element, path, archetype_id, containers)
      {
        "schema_version" => "1.2",
        "identity" => {
          "template_id" => @template.template_id,
          "archetype_id" => archetype_id,
          "path" => "#{path}/value",
          "at_code" => element.node_id
        },
        "semantics" => semantics_for(archetype_id, element.node_id, element, containers),
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

    def semantics_for(archetype_id, at_code, element, containers)
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
        "container_labels" => containers,
        "rm_type" => rm_type_for(element)
      }
      alternatives = value_attribute_children(element)
      if alternatives.size >= 2
        semantics["rm_type_alternatives"] = alternatives.map(&:rm_type_name)
      end
      semantics
    end

    # 祖先ルート名（スキーマ v1.2 `semantics.container_labels`、skoba/anlage#31）。
    #
    # 取り込み元は `source_xml` の再解析（`extract_root_names`）。gem のパース結果は
    # 各 C_ARCHETYPE_ROOT 直下の term_definitions を `component_terminologies[archetype_id]`
    # に畳み込み、同一アーキタイプの複数埋め込み（紹介元／紹介先の organisation 等）で
    # per-root の名前（AD の改名 = at0000 text）を失う（`skoba/openehr-ruby#58`、
    # `docs/upstream-candidates.md` 18 項）。WP2 の「経路2」（term_bindings 再解析、#19 で
    # 撤去）と同型の迂回。
    # 撤去条件: openehr-ruby#58 が解消し `CArchetypeRoot` が per-root の term_definitions を
    # 持つ版へ bump した時点で、`extract_root_names` を gem 経路へ置換する。
    #
    # キーは「archetype_id 述語で書いたルートの RM path」＋「同 path 内の出現順」。
    # 前提: OPT XML の文書順（Nokogiri の xpath 結果順）と、gem がパースした
    # attributes/children の走査順（本 walk の順）が一致すること。両者は同じ XML の
    # 同じ要素列から作られるが、この前提が崩れると同 path の複数ルート（紹介元／紹介先）
    # の名前が入れ替わる。spec（pathcard_extractor_spec「同一アーキタイプの複数ルート」）で
    # 固定している。
    def container_labels_for(path, archetype_id, parent_containers)
      index = @root_occurrences[path]
      @root_occurrences[path] += 1
      text = @root_names.fetch(path, [])[index]

      unless text
        (@report[:missing_container_labels] ||= []) << {
          "archetype_id" => archetype_id,
          "path" => path
        }
        return parent_containers
      end

      entry = {
        "lang" => @opt.original_language.code_string,
        "text" => text,
        "archetype_id" => archetype_id
      }.merge(classify_translation(text))
      parent_containers + [ entry ]
    end

    # source_xml を再解析し、C_ARCHETYPE_ROOT ごとの at0000 text を
    # { rm_path => [text, ...（文書順）] } で返す。path の書式は walk と同じ
    # （属性名 + `[archetype_id]` または `[node_id]`）。
    def extract_root_names(source_xml)
      document = Opt::SafeParser.safe_document(source_xml)
      document.remove_namespaces!

      names = Hash.new { |hash, key| hash[key] = [] }
      document.xpath("//*[@type='C_ARCHETYPE_ROOT']").each do |root|
        text = root.at_xpath("./term_definitions[@code='at0000']/items[@id='text']")&.text
        names[root_rm_path(root)] << text
      end
      names
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
