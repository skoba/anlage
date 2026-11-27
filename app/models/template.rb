require "digest"

class Template < ApplicationRecord
  class InvalidTemplate < StandardError; end

  STATUSES = %w[active superseded].freeze

  validates :template_id, presence: true
  validates :version, presence: true
  validates :checksum, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :template_id, uniqueness: { scope: :version }

  scope :active, -> { where(status: "active") }

  has_many :compositions, dependent: :destroy

  # Parses raw OPT XML, and returns a not-yet-persisted Template with
  # template_id/checksum/web_template filled in from the parse. Does not
  # save -- callers decide what to do on checksum collision (see
  # Templates::PreviewSummary / Templates#create).
  def self.build_from_opt_xml(source_xml)
    opt = Opt::SafeParser.parse(source_xml)
    raise InvalidTemplate, "template has no template_id" if opt.template_id.value.to_s.empty?

    extractor = OpenehrRails::Opt::FieldExtractor.new(opt)
    new(
      template_id: opt.template_id.value,
      version: "1.0.0",
      source_xml: source_xml,
      web_template: build_web_template(opt, extractor),
      status: "active",
      checksum: Digest::SHA256.hexdigest(source_xml)
    )
  rescue InvalidTemplate, Opt::UnsafeTemplate
    raise
  rescue StandardError => e
    raise InvalidTemplate, "not a valid operational template: #{e.message}"
  end

  def self.find_by_checksum(source_xml)
    find_by(checksum: Digest::SHA256.hexdigest(source_xml))
  end

  # Bumps the patch segment of a dotted version string ("1.0.0" ->
  # "1.0.1"); used when a dropped OPT shares a template_id with an
  # already-registered active template but has different content.
  def self.next_version(version)
    parts = version.split(".")
    parts[-1] = (parts.last.to_i + 1).to_s
    parts.join(".")
  end

  def supersede!
    update!(status: "superseded")
  end

  # web_template は登録時に固定される。同一 checksum の再投入は「already registered」で
  # 再構築されないため、field の導出規則（input_kind 等）を変えた後は
  # `rake templates:rebuild_web_template` でこれを呼ぶ（skoba/anlage#33 裁定 C）。
  # checksum・pathcards・status は変えない。
  def rebuild_web_template!
    opt = Opt::SafeParser.parse(source_xml)
    update!(web_template: self.class.send(:build_web_template, opt, OpenehrRails::Opt::FieldExtractor.new(opt)))
  end

  def self.build_web_template(opt, extractor)
    terms = Opt::RootTerms.call(opt)
    root_occurrences = Hash.new(0)
    # 各 field が属するルート（インスタンス）。field の path と instance_index で結ぶ（skoba/anlage#117。
    # OPT には content の外〔context〕にも ELEMENT があるので、並び順だけでは結べない）
    element_roots = Opt::ElementRoots.call(opt).group_by { |element| element["path"] }
    web_template = {
      "template_id" => opt.template_id.value,
      "concept" => opt.concept,
      # COMPOSITION アーキタイプの ID（definition ルート）。保存する Composition のルートに使う（skoba/anlage#54）
      "root_archetype_id" => opt.definition.archetype_id.value,
      "sem_ver" => opt.description&.other_details&.dig("sem_ver").presence,
      # OPT が COMPOSITION の category を 1 つのコードに絞っていれば、そのコード（skoba/anlage#87）
      "category_code" => category_code(opt),
      # SECTION ルートの path → テンプレート上の名前。builder が SECTION の name に使う（skoba/anlage#80）
      "section_labels" => section_labels(terms),
      "entries" => uniquify_field_names(extractor.entries.map { |entry| serialize_entry(entry, instance_terms(entry, terms, root_occurrences), terms, element_roots) })
    }
    # 保存可否は登録時に一度だけ判定（skoba/anlage#36）
    web_template.merge(Opt::FormCapability.call(web_template))
  end

  # #54 より前に登録された web_template にはキーが無いので、そのときは OPT から引く
  # （rebuild_web_template! を呼べば web_template に入る）。
  def root_archetype_id
    (web_template || {})["root_archetype_id"] || Opt::SafeParser.parse(source_xml).definition.archetype_id.value
  end

  def preview_only?
    (web_template || {})["form_capability"] == "preview_only"
  end

  def form_capability_reason
    (web_template || {})["form_capability_reason"]
  end

  # OPT 自身の版（other_details の sem_ver）。登録版 version と並記する（skoba/anlage#47）
  def sem_ver
    (web_template || {})["sem_ver"]
  end

  # facade（Fhir::ProfilesController）と同じ ProfileGenerator から導く（skoba/anlage#47）
  def fhir_profile_ids
    OpenehrRails::Fhir::ProfileGenerator.new(OpenehrRails::Opt.parse(source_xml)).profiles.map { _1[:id] }
  end

  # 埋め込みルート配下の field（skoba/anlage#38）に、そのルートのテンプレート上の名前（root_label）を足す。
  # builder が CLUSTER の name に使う。path・name・archetype_id・root_path は openehr-rails 0.9.0 の
  # FieldExtractor がそのまま出す（上流候補 22 項。anlage の訂正は #111 で撤去）。
  # 埋め込みルート配下の field の、entry より奥のルートの並び（外側から）。各ルートはインスタンスで区別し、
  # テンプレート上の名前を持つ（skoba/anlage#117）。builder はこれで CLUSTER をインスタンスごとに分け、名前を付ける。
  # element が FieldExtractor の field と結べない（path が違う）ときは nil（これまでの組み方に落ちる）。
  def self.root_chain(field, entry, terms, element)
    return unless element && element["path"] == field["path"]

    roots = element["roots"]
    entry_index = roots.index { |archetype_id, *| archetype_id == entry[:archetype_id] }
    return unless entry_index

    roots.drop(entry_index + 1).map do |archetype_id, path, occurrence, _min|
      { "archetype_id" => archetype_id, "index" => occurrence,
        "label" => terms.fetch(path, [])[occurrence]&.dig("at0000", "text") || archetype_id.split(".")[1] }
    end
  end

  # field を含む入れ物（ENTRY と埋め込み CLUSTER）を外側から並べる（R-20261125-1。必須の規則は「入れ物を書くなら必須」、
  # Opt::FormValidator）。key は OPT 上の path と出現順（インスタンスを区別する）、min は occurrences の下限（無ければ nil）。
  # ELEMENT が引けない field（path の書式が合わない）には付けない（validator はこれまでどおり下限 ≥1 を必須とする）
  def self.containers(field, entry, element)
    return unless element && element["path"] == field["path"]

    roots = element["roots"]
    entry_index = roots.index { |archetype_id, *| archetype_id == entry[:archetype_id] }
    return unless entry_index

    roots.drop(entry_index).map { |_archetype_id, path, occurrence, min| { "key" => "#{path}##{occurrence}", "min" => min } }
  end

  # 同じ名前の field（同じアーキタイプの複数ルート）は、文書順で 2 つめ以降に _2・_3 を付ける（skoba/anlage#117。
  # openehr-rails 0.8.0 までの FieldExtractor の付け方〔…_at0001_2〕にならう）
  def self.uniquify_field_names(entries)
    seen = Hash.new(0)
    entries.each do |entry|
      entry["fields"].each do |field|
        seen[field["name"]] += 1
        field["name"] = "#{field['name']}_#{seen[field['name']]}" if seen[field["name"]] > 1
      end
    end
  end

  def self.category_code(opt)
    category = opt.definition.attributes&.find { |attribute| attribute.rm_attribute_name == "category" }
    codes = category&.children&.flat_map { |child| child.attributes || [] }
                    &.select { |attribute| attribute.rm_attribute_name == "defining_code" }
                    &.flat_map { |attribute| attribute.children || [] }
                    &.flat_map { |code_phrase| code_phrase.respond_to?(:code_list) ? Array(code_phrase.code_list) : [] }
    codes.first if codes&.size == 1
  end

  def self.section_labels(terms)
    terms.select { |path, _| path.match?(/\[openEHR-EHR-SECTION\.[^\]]+\]\z/) }
         .transform_values { |instances| instances.first&.dig("at0000", "text") }.compact
  end

  def self.instance_terms(entry, terms, root_occurrences)
    root_path = (entry[:fields] || []).map { |f| f[:path].to_s[/\A.*\[openEHR-EHR-[^\]]+\]/] }.compact.min_by(&:length)
    return {} unless root_path

    index = root_occurrences[root_path]
    root_occurrences[root_path] += 1
    terms.fetch(root_path, [])[index] || {}
  end

  # gem（openehr-rails 0.9.0）の field に Anlage 側のキーを足す。path・name・値の代替型・occurrences 下限・
  # 単位の一覧は gem の値をそのまま使う（上流候補 19・20・22 項。anlage の走査 Opt::ElementConstraints は #111 で撤去）:
  #   label: 同じアーキタイプの複数 ENTRY（clinical_synopsis ×2）は、ルート（インスタンス）ごとの名前
  #     （gem のラベルは後勝ち）。entries の並び＝文書順で出現順に結ぶ
  #   root_label: 埋め込みルート配下の field の、ルートのテンプレート上の名前（#38）
  #   input_kind: フォーム入力の方針属性（Opt::InputKind、登録時に一度だけ導出、#33）
  #   required: 要素自身の下限 ≥1 も required とする。意味は「要素を含む入れ物を書くなら必須」（R-20261125-1、containers）（#34。gem の required は「entry が必須 かつ
  #     要素が必須」の意味のままで、0..1 の entry 配下では 1..1 の要素も false）
  #   units_list: 数量でない field は空（gem は nil）
  def self.serialize_entry(entry, instance_terms = {}, terms = {}, element_roots = nil)
    fields = (entry[:fields] || []).map do |field|
      # openehr-rails 0.12.0 の field の root_chain・root_label（gem の形）は持ち込まない。anlage の形で下で組む（R-20261127-9）
      field = field.stringify_keys.except("root_chain", "root_label")
      element = element_roots&.fetch(field["path"], nil)&.at(field["instance_index"].to_i)
      instance_label = instance_terms.dig(field["node_id"], "text") if field["archetype_id"] == entry[:archetype_id]
      field["label"] = instance_label if instance_label.present?
      chain = root_chain(field, entry, terms, element)
      field = field.merge("root_chain" => chain, "root_label" => chain.last["label"]) if chain.present?
      containers = containers(field, entry, element)
      field = field.merge("containers" => containers) if containers
      field.merge(
        "input_kind" => Opt::InputKind.for(field, field["rm_type_alternatives"]),
        "required" => field["required"] || field["min_occurrences"].to_i >= 1,
        "units_list" => field["units_list"] || []
      )
    end
    entry.merge(occurrences: interval_to_h(entry[:occurrences]), fields: fields).stringify_keys
         .merge(entry_labels(entry, fields, instance_terms))
  end

  # この ENTRY のルート（インスタンス）のテンプレート上の名前（label）と、field の path に現れる
  # 構造ノード（HISTORY・EVENT・ITEM_TREE など、at-code を持つ途中のノード）の名前（node_labels）。
  # builder がノードの name に使う（skoba/anlage#109）。用語が無いものは入れない。
  def self.entry_labels(entry, fields, instance_terms)
    codes = fields.select { |field| field["archetype_id"] == entry[:archetype_id] }
                  .flat_map { |field| field["path"].to_s.scan(/\[(at[\d.]+)\]/).flatten[0...-1] }.uniq
    node_labels = codes.to_h { |code| [ code, instance_terms.dig(code, "text") ] }.compact
    { "label" => instance_terms.dig("at0000", "text"), "node_labels" => node_labels }.compact
  end

  def self.interval_to_h(interval)
    return nil unless interval

    { "lower" => interval.lower, "upper" => interval.upper }
  end
  private_class_method :build_web_template, :serialize_entry, :root_chain, :containers, :uniquify_field_names, :interval_to_h, :section_labels, :category_code, :entry_labels

  def entries
    (web_template || {})["entries"] || []
  end

  def fields
    entries.flat_map { |entry| entry["fields"] || [] }
  end
end
