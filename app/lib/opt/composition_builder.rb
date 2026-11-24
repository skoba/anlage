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

    # gem全体の唯一の実測慣例値。OPT・gem設定のいずれにも情報源なし
    RM_VERSION = "1.0.4"

    # openEHR 用語（terminology id "openehr"）の composition category グループの rubric
    COMPOSITION_CATEGORY_LABELS = { "431" => "persistent", "433" => "event" }.freeze

    ENTRY_CLASSES = {
      "OBSERVATION" => OpenEHR::RM::Composition::Content::Entry::Observation,
      "EVALUATION" => OpenEHR::RM::Composition::Content::Entry::Evaluation,
      "ADMIN_ENTRY" => OpenEHR::RM::Composition::Content::Entry::AdminEntry,
      "INSTRUCTION" => OpenEHR::RM::Composition::Content::Entry::Instruction
    }.freeze

    # ACTIVITY.action_archetype_id は OPT の制約から取り、制約が無ければ任意の ACTION を許す（R-20261124-5）。
    # 手元の実物の OPT（spec/fixtures/opt/ の 6 つ）には制約を持つものが無いので、いまは既定値だけ（skoba/anlage#30）
    DEFAULT_ACTION_ARCHETYPE_ID = "/.*/"

    # narrative（案 B、R-20261124-14）のつなぎ方。docs/design/rm-attributes-without-inputs.md 6 節。
    # DV_TEXT は改行を持てない（RM の不変条件。openehr 2.5.0 rm/data_types/text.rb:102-106）ので、
    # 要素の区切りは全角のセミコロン（値の側も DV_TEXT なので、改行は入らない）
    NARRATIVE_SEPARATOR = "；"

    def initialize(template, values)
      @template = template
      @values = values.stringify_keys
    end

    def build
      OpenEHR::RM::Composition::Composition.new(
        # ルートは COMPOSITION アーキタイプの ID。template_id は archetype_details に入る（skoba/anlage#54）
        archetype_node_id: @template.root_archetype_id,
        archetype_details: archetyped(@template.root_archetype_id),
        name: dv_text(@template.web_template["concept"] || @template.template_id),
        language: code_phrase(OpenehrRails.default_language, "ISO_639-1"),
        territory: code_phrase(OpenehrRails.default_territory, "ISO_3166-1"),
        category: category,
        composer: OpenEHR::RM::Common::Generic::PartyIdentified.new(name: OpenehrRails.default_composer_name),
        content: build_content
      )
    end

    # build が「正しく」組めない形の理由（skoba/anlage#80、R-20261124-5 問い 2）。build のドライランでは
    # 見えないものを挙げる: field を持たず空 entry として飛ばされる未対応クラスの entry（INSTRUCTION）と、
    # 複数の field で衝突する名前（値が 1 つの入力から複数のルートに入ってしまう）。
    def unsupported_reasons
      rm_types = @template.entries.map { |entry| entry["rm_type"] }.uniq.reject { |rm_type| ENTRY_CLASSES.key?(rm_type) }
      shared = @template.fields.map { |field| field["name"] }.tally.select { |_name, count| count > 1 }

      rm_types.map { |rm_type| "entry rm_type #{rm_type} is not supported yet" } +
        shared.map { |name, count| "field name #{name} is shared by #{count} fields" }
    end

    private

    # 全要素が空欄の entry は含めない（skoba/anlage#34）。SECTION 配下の entry は、path の
    # SECTION の並びどおりに SECTION（入れ子も可）を作って、その items に入れる（skoba/anlage#80）。
    # SECTION は、配下に組む entry があるときだけ作る。
    def build_content
      root = { items: [] }
      @template.entries.reject { |entry| filled_fields(entry).empty? }.each do |entry|
        node = section_chain(entry).inject(root) do |parent, (attr, archetype_id)|
          path = "#{parent[:path]}/#{attr}[#{archetype_id}]"
          parent[:items].find { |item| item.is_a?(Hash) && item[:path] == path } ||
            { path: path, archetype_id: archetype_id, items: [] }.tap { |section| parent[:items] << section }
        end
        node[:items] << build_entry(entry)
      end
      root[:items].map { |item| build_section(item) }
    end

    def build_section(item)
      return item unless item.is_a?(Hash)

      OpenEHR::RM::Composition::Content::Navigation::Section.new(
        archetype_node_id: item[:archetype_id],
        name: dv_text(@template.web_template.dig("section_labels", item[:path]) || item[:archetype_id].split(".")[1]),
        archetype_details: archetyped(item[:archetype_id]),
        items: item[:items].map { |child| build_section(child) }
      )
    end

    # entry より外側の segment（SECTION の並び）。[[attr, archetype_id], ...]、外側から。
    def section_chain(entry)
      chains = filled_fields(entry).map do |field|
        segments = path_segments(field["path"])
        segments[0...entry_index(segments, entry)]
      end.uniq
      raise UnsupportedShape, "entry #{entry['archetype_id']} fields span more than one container (#{chains.inspect})" unless chains.size == 1

      chains.first
    end

    def path_segments(path)
      path.split("/").reject(&:empty?).map { |seg| seg.match(/\A(\w+)(?:\[(.+)\])?\z/).captures }
    end

    def entry_index(segments, entry)
      segments.index { |_attr, node_id| node_id == entry["archetype_id"] } ||
        raise(UnsupportedShape, "entry #{entry['archetype_id']} is not on its field path")
    end

    def build_entry(entry)
      klass = ENTRY_CLASSES.fetch(entry["rm_type"]) do
        raise UnsupportedShape, "entry rm_type #{entry['rm_type']} is not supported yet"
      end

      branches = branches_of(entry, klass)
      attributes = {
        archetype_node_id: entry["archetype_id"],
        archetype_details: archetyped(entry["archetype_id"]),
        # name はテンプレート上の名前。キーが無い登録済みの web_template では concept（skoba/anlage#109）
        name: dv_text(entry["label"] || entry["concept"]),
        language: code_phrase(OpenehrRails.default_language, "ISO_639-1"),
        encoding: code_phrase(OpenehrRails.default_encoding, "IANA_character-sets"),
        subject: OpenEHR::RM::Common::Generic::PartySelf.new(external_ref: nil)
      }
      if klass == ENTRY_CLASSES["INSTRUCTION"]
        # INSTRUCTION（skoba/anlage#30）: ACTIVITY は 1 つ（jp_referral の activities[at0001]）。timing は付けない（R-20261124-5）
        attributes[:activities] = [ build_activity(entry, branches.fetch("activities", [])) ]
        attributes[:narrative] = dv_text(narrative(entry))
      else
        attributes[:data] = build_data(entry, branches.fetch("data", []))
      end
      # protocol は、値が入った要素があるときだけ付ける（skoba/anlage#111）
      attributes[:protocol] = build_protocol(entry, branches["protocol"]) if (branches["protocol"] || []).intersect?(filled_fields(entry))
      klass.new(**attributes)
    end

    # entry の field を、entry 直下の属性（data／protocol）ごとに分ける（skoba/anlage#111。openehr-rails 0.9.0 から
    # protocol 配下の ELEMENT も field になる）。値が入っているのに組めない属性があれば UnsupportedShape。
    BRANCHES = {
      "data" => ENTRY_CLASSES.values_at("OBSERVATION", "EVALUATION", "ADMIN_ENTRY"),
      "protocol" => ENTRY_CLASSES.values_at("OBSERVATION", "EVALUATION", "INSTRUCTION"),
      "activities" => ENTRY_CLASSES.values_at("INSTRUCTION")
    }.freeze

    def branches_of(entry, klass)
      branches = (entry["fields"] || []).group_by { |field| wrapper_chain(field["path"], entry).first&.first }
      filled = filled_fields(entry)
      unsupported = branches.select { |attr, fields| fields.intersect?(filled) && !BRANCHES.fetch(attr, []).include?(klass) }.keys
      raise UnsupportedShape, "entry #{entry['archetype_id']} has fields under #{unsupported.join(', ')}, which is not supported yet for #{entry['rm_type']}" if unsupported.any?

      branches
    end

    # 送信値が blank（nil／""）の要素は Composition に含めない（skoba/anlage#34。要素単位・
    # 型別ガードにしない）。build_value が送信値へ直接 Float／Integer／Date.parse／
    # Time.zone.parse／iso8601 を呼ぶのは、ここを通った非 blank の要素だけ。
    def filled_fields(entry)
      (entry["fields"] || []).reject { |field| @values[field["name"]].blank? }
    end

    # 埋め込み CLUSTER 一段（skoba/anlage#38）: 全 field に共通の枝（ITEM_TREE まで）を取り、
    # その先に `items[<archetype_id>]` 一段だけ残る field は CLUSTER（archetype_details 付き）に
    # まとめる。二段以上は UnsupportedShape のまま（#30 と同じ 12 月）。
    def build_data(entry, branch_fields)
      item_tree, outer_segs = build_branch(entry, branch_fields)

      case entry["rm_type"]
      when "OBSERVATION"
        wrap_in_history(outer_segs.reverse, item_tree, entry)
      else
        raise UnsupportedShape, "unexpected wrapper depth for #{entry['rm_type']}" if outer_segs.any?

        item_tree
      end
    end

    # activities[atX]/description[atY] の ITEM_TREE を description に持つ ACTIVITY（skoba/anlage#30）
    def build_activity(entry, branch_fields)
      description, outer_segs = build_branch(entry, branch_fields)
      raise UnsupportedShape, "unexpected wrapper depth for the activities of #{entry['rm_type']}" unless outer_segs.size == 1

      _attr, node_id = outer_segs.first
      OpenEHR::RM::Composition::Content::Entry::Activity.new(
        archetype_node_id: node_id,
        name: dv_text(node_label(entry, node_id) || "activity"),
        description: description,
        action_archetype_id: DEFAULT_ACTION_ARCHETYPE_ID
      )
    end

    # 案 B（R-20261124-14）: entry の配下で入力された要素を、文書順（web_template の並び）に「ラベル: 値」で
    # 改行でつなぐ。埋め込みルートの要素は「ルートの名前／ラベル」。値は帳票で見えるとおり（選択肢は表示名、
    # 数量は単位付き、日時は時刻付き）。生成系は使わない
    def narrative(entry)
      filled_fields(entry).map do |field|
        label = field["archetype_id"] == entry["archetype_id"] || field["root_label"].blank? ? field["label"] : "#{field['root_label']}／#{field['label']}"
        "#{label}: #{narrative_value(field)}"
      end.join(NARRATIVE_SEPARATOR)
    end

    def narrative_value(field)
      raw = @values[field["name"]].to_s
      case field["input_kind"]
      when "select" then field.dig("code_labels", raw) || raw
      when "number" then [ raw, Opt::FormValidator.units_for(field, @values) ].compact_blank.join(" ")
      when "datetime" then [ raw, @values["#{field['name']}__time"] ].compact_blank.join(" ")
      else raw
      end
    end

    def build_protocol(entry, branch_fields)
      item_tree, outer_segs = build_branch(entry, branch_fields)
      raise UnsupportedShape, "unexpected wrapper depth for the protocol of #{entry['rm_type']}" if outer_segs.any?

      item_tree
    end

    # 1 つの属性（data／protocol）の配下の field から、ITEM_TREE と、その外側の segment を返す。
    # 骨格（ITEM_TREE までの枝）は、その属性の全 field の path から取る。値が入った要素だけを items に入れる
    # （data に値が無く protocol だけに値があるときは、data は要素の無い ITEM_TREE になる）。
    def build_branch(entry, branch_fields)
      raise UnsupportedShape, "entry #{entry['archetype_id']} has no fields" if branch_fields.blank?

      # 骨格は、最初の埋め込みルートより手前の segment。属性の全 field で同じでなければならない
      chains = branch_fields.map { |f| wrapper_chain(f["path"], entry) }
      skeletons = chains.map { |chain| chain.take_while { |_attr, node_id| !archetype_root?(node_id) } }.uniq
      raise UnsupportedShape, "entry #{entry['archetype_id']} fields span more than one branch (#{skeletons.inspect})" unless skeletons.size == 1

      common = skeletons.first
      filled = filled_fields(entry)
      # 埋め込みルートより奥の segment（多段の埋め込み CLUSTER、skoba/anlage#30）。ルート以外のノードは未対応
      pairs = branch_fields.zip(chains).filter_map do |field, chain|
        rest = chain[common.size..]
        bad = rest.find { |_attr, node_id| !archetype_root?(node_id) }
        raise UnsupportedShape, "entry #{entry['archetype_id']}: embedded node #{bad.inspect} is not an archetype root" if bad

        [ field, rest.map(&:last) ] if filled.include?(field)
      end

      item_tree_seg, *outer_segs = common.reverse
      [ build_item_tree(item_tree_seg, entry, pairs), outer_segs ]
    end

    def archetype_root?(node_id)
      node_id.to_s.start_with?("openEHR-")
    end

    # pairs: [[field, [埋め込みルートの archetype_id, ...（外側から）]], ...]。文書順に、要素はそのまま、
    # 埋め込みルートは CLUSTER（archetype_details 付き）にまとめて、その中を同じ規則で組む
    def build_items(pairs)
      pairs.group_by { |_field, roots| roots.first }.flat_map do |root, group|
        next group.map { |field, _roots| build_element(field) } unless root

        inner = group.map { |field, roots| [ field, roots.drop(1) ] }
        [ build_cluster(root, inner) ]
      end
    end

    # [[attr, node_id], ...] from outermost to innermost, excluding everything
    # up to and including the entry's own segment (content[...] or, under
    # SECTIONs, .../items[<entry archetype_id>]), the trailing "value" leaf and
    # the ELEMENT's own "items[node_id]" segment (handled per-field).
    def wrapper_chain(path, entry)
      segments = path_segments(path)
      segments[(entry_index(segments, entry) + 1)...-2]
    end

    def build_item_tree(item_tree_seg, entry, pairs)
      _attr, node_id = item_tree_seg
      OpenEHR::RM::DataStructures::ItemStructure::ItemTree.new(
        archetype_node_id: node_id,
        name: dv_text(node_label(entry, node_id) || entry["concept"]),
        items: build_items(pairs)
      )
    end

    # CLUSTER の name は、そのルートの直下の要素の root_label（テンプレート上の名前）。直下に入力が無ければ、
    # 奥の要素のラベルからは取れないので、アーキタイプの概念名に落とす
    def build_cluster(archetype_id, inner)
      own = inner.find { |field, roots| roots.empty? && field["archetype_id"] == archetype_id }&.first
      label = own&.fetch("root_label", nil) || root_label_of(archetype_id)
      OpenEHR::RM::DataStructures::ItemStructure::Representation::Cluster.new(
        archetype_node_id: archetype_id,
        name: dv_text(label || archetype_id.split(".")[1]),
        archetype_details: archetyped(archetype_id),
        items: build_items(inner)
      )
    end

    # 同じアーキタイプの field の root_label（直下に入力が無い CLUSTER の名前に使う。web_template の文書順で最初のもの）
    def root_label_of(archetype_id)
      @template.fields.find { |field| field["archetype_id"] == archetype_id && field["root_label"].present? }&.fetch("root_label")
    end

    # outer_segs: [[HISTORY attr, node_id], [EVENT attr, node_id]], outermost first.
    def wrap_in_history(outer_segs, item_tree, entry)
      raise UnsupportedShape, "OBSERVATION without a HISTORY/EVENT wrapper" unless outer_segs.size == 2

      (_, history_node_id), (_, event_node_id) = outer_segs

      event = OpenEHR::RM::DataStructures::History::PointEvent.new(
        archetype_node_id: event_node_id,
        name: dv_text(node_label(entry, event_node_id) || "event"),
        time: dv_date_time(Time.current),
        data: item_tree
      )

      OpenEHR::RM::DataStructures::History::History.new(
        archetype_node_id: history_node_id,
        name: dv_text(node_label(entry, history_node_id) || "history"),
        origin: dv_date_time(Time.current),
        events: [ event ]
      )
    end

    def build_element(field)
      OpenEHR::RM::DataStructures::ItemStructure::Representation::Element.new(
        archetype_node_id: field["node_id"],
        name: dv_text(field["label"]),
        value: build_value(field, @values[field["name"]])
      )
    end

    def build_value(field, raw_value)
      # 方針は input_kind を読むだけ（#33 裁定 A）。coded_free は OR 制約の正規の一方
      # （DV_TEXT）で保存し、coded_manual は手入力の system／code で DvCodedText を組む。
      # 型の構築自体は rm_type（モデルの事実）による。
      case field["input_kind"]
      when "number"
        return OpenEHR::RM::DataTypes::Quantity::DvCount.new(magnitude: Integer(raw_value)) if field["rm_type"] == "DV_COUNT" && !Array(field["rm_type_alternatives"]).include?("DV_QUANTITY")

        # #37: 単位は __units（無ければ units リストの先頭）
        return OpenEHR::RM::DataTypes::Quantity::DvQuantity.new(magnitude: Float(raw_value), units: Opt::FormValidator.units_for(field, @values).to_s)
      when "coded_free"
        return dv_text(raw_value.to_s)
      when "coded_manual"
        system = @values["#{field['name']}__system"].presence || field["value_set_uri"].to_s.delete_prefix("terminology:")
        return dv_coded_text(raw_value.to_s, @values.fetch("#{field['name']}__code"), system)
      when "date"
        return OpenEHR::RM::DataTypes::Quantity::DateTime::DvDate.new(value: raw_value.to_s)
      when "time"
        return OpenEHR::RM::DataTypes::Quantity::DateTime::DvTime.new(value: raw_value.to_s)
      when "datetime"
        time = @values["#{field['name']}__time"]
        return dv_date_time_partial(time.present? ? "#{raw_value}T#{time}" : raw_value.to_s)
      end

      case field["rm_type"]
      when "DV_QUANTITY"
        OpenEHR::RM::DataTypes::Quantity::DvQuantity.new(magnitude: Float(raw_value), units: field["units"])
      when "DV_COUNT"
        OpenEHR::RM::DataTypes::Quantity::DvCount.new(magnitude: Integer(raw_value))
      when "DV_CODED_TEXT"
        dv_coded_text(field.dig("code_labels", raw_value) || raw_value, raw_value, field["terminology_id"] || "local")
      when "DV_BOOLEAN"
        OpenEHR::RM::DataTypes::Basic::DvBoolean.new(value: ActiveModel::Type::Boolean.new.cast(raw_value))
      else
        dv_text(raw_value.to_s)
      end
    end

    # OPT が絞っているコード（web_template["category_code"]）を使い、無ければ設定の既定値
    # （OpenehrRails.default_category は [コード, 表示] の順）。表示は openEHR 用語の
    # composition category の rubric（skoba/anlage#87）。
    def category
      default_code, default_label = OpenehrRails.default_category
      code = @template.web_template["category_code"] || default_code
      label = COMPOSITION_CATEGORY_LABELS[code] || (default_label if code == default_code) ||
              raise(UnsupportedShape, "composition category code #{code} has no known label")
      dv_coded_text(label, code, "openehr")
    end

    # 構造ノード（HISTORY・EVENT・ITEM_TREE）の、テンプレートの用語での名前（skoba/anlage#109）
    def node_label(entry, node_id)
      entry.dig("node_labels", node_id)
    end

    def archetyped(archetype_id)
      OpenEHR::RM::Common::Archetyped::Archetyped.new(
        archetype_id: OpenEHR::RM::Support::Identification::ArchetypeID.new(value: archetype_id),
        template_id: OpenEHR::RM::Support::Identification::TemplateID.new(value: @template.web_template["template_id"]),
        rm_version: RM_VERSION
      )
    end

    def dv_text(value)
      OpenEHR::RM::DataTypes::Text::DvText.new(value: value.to_s)
    end

    def dv_coded_text(value, code, terminology)
      OpenEHR::RM::DataTypes::Text::DvCodedText.new(value: value, defining_code: code_phrase(code, terminology))
    end

    def code_phrase(code, terminology)
      OpenEHR::RM::DataTypes::Text::CodePhrase.new(
        # value: で組む。name: で組むと RMJSONSerializer が値を出さない（skoba/anlage#86、
        # docs/upstream-candidates.md 26 項）
        terminology_id: OpenEHR::RM::Support::Identification::TerminologyID.new(value: terminology),
        code_string: code
      )
    end

    def dv_date_time(time)
      OpenEHR::RM::DataTypes::Quantity::DateTime::DvDateTime.new(value: time.iso8601)
    end

    # ISO 部分精度の文字列をそのまま DvDateTime に載せる（skoba/anlage#35）。存在しない精度
    # （午前 0 時・秒・タイムゾーン）を付けない。
    # openehr-ruby 2.4.3 の ISO8601DateTime は `T` と時（hh）を必須にし、日付のみ
    # （YYYY-MM-DD）を拒否する（skoba/openehr-ruby#59）。日付のみは Opt::FormValidator で
    # 形式検証済みなので、gem の検証を通る時刻付きの値で構築してから @value を差し替える
    # 暫定。撤去条件: openehr-ruby#59 の解消版へ bump した時点で DvDateTime.new(value:) に戻す。
    def dv_date_time_partial(value)
      klass = OpenEHR::RM::DataTypes::Quantity::DateTime::DvDateTime
      return klass.new(value: value) if value.include?("T")

      klass.new(value: "#{value}T00").tap { |dv| dv.instance_variable_set(:@value, value) }
    end
  end
end
