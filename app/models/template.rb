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
      web_template: build_web_template(opt, extractor, source_xml),
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
    update!(web_template: self.class.send(:build_web_template, opt, OpenehrRails::Opt::FieldExtractor.new(opt), source_xml))
  end

  def self.build_web_template(opt, extractor, source_xml)
    constraints = Opt::ElementConstraints.call(opt)
    terms = Opt::TemplateTerms.call(source_xml)
    root_occurrences = Hash.new(0)
    web_template = {
      "template_id" => opt.template_id.value,
      "concept" => opt.concept,
      "entries" => extractor.entries.map { |entry| serialize_entry(entry, constraints, instance_terms(entry, terms, root_occurrences), terms) }
    }
    # 保存可否は登録時に一度だけ判定（skoba/anlage#36）
    web_template.merge(Opt::FormCapability.call(web_template))
  end

  def preview_only?
    (web_template || {})["form_capability"] == "preview_only"
  end

  def form_capability_reason
    (web_template || {})["form_capability_reason"]
  end

  # ENTRY 自身のルート（インスタンス）の term_definitions。同一アーキタイプの複数 ENTRY
  # （clinical_synopsis ×2）は entries の並び＝文書順で出現順に結ぶ。埋め込み CLUSTER
  # ルート配下の field は gem のラベルのまま（現 fixture に複数インスタンスの例が無い）。
  # 埋め込み CLUSTER 配下の field（skoba/anlage#38）: path を archetype_id 述語に訂正し、
  # archetype_id を自ルートに、name を自アーキタイプで名前空間化（laboratory_test_analyte_at0001）、
  # root_label にそのルートのテンプレート名を持たせる（builder が CLUSTER の name に使う）。
  def self.rewrite_embedded_field(field, corrected_path, constraint, entry, terms)
    own_archetype_id = constraint.fetch("archetype_id", field["archetype_id"])
    field["path"] = corrected_path
    return field if own_archetype_id == entry[:archetype_id]

    concept = own_archetype_id.split(".")[1].to_s.gsub(/[^a-zA-Z0-9]+/, "_")
    root_terms = terms.fetch(constraint["root_path"], []).first || {}
    field.merge(
      "archetype_id" => own_archetype_id,
      "name" => "#{concept}_#{field['node_id']}",
      "root_path" => constraint["root_path"],
      "root_label" => root_terms.dig("at0000", "text") || concept
    )
  end

  def self.instance_terms(entry, terms, root_occurrences)
    root_path = (entry[:fields] || []).map { |f| f[:path].to_s[/\A.*\[openEHR-EHR-[^\]]+\]/] }.compact.min_by(&:length)
    return {} unless root_path

    index = root_occurrences[root_path]
    root_occurrences[root_path] += 1
    terms.fetch(root_path, [])[index] || {}
  end

  # gem の field に Anlage 側のキーを additive に足す:
  #   rm_type_alternatives: value 属性の代替 RM 型（OPT 出現順、#33）
  #   input_kind: フォーム入力の方針属性（Opt::InputKind、登録時に一度だけ導出、#33）
  #   min_occurrences / required: 要素の occurrences 下限（#34。gem の required は
  #     「entry が必須 かつ 要素が必須」で 0..1 の entry 配下では常に false なので、
  #     要素自身の下限 ≥1 を required とする）
  def self.serialize_entry(entry, constraints, instance_terms = {}, terms = {})
    by_gem_path = Opt::ElementConstraints.by_gem_path(constraints)
    gem_path_seen = Hash.new(0)
    fields = (entry[:fields] || []).map do |field|
      field = field.stringify_keys
      # gem の path（埋め込みルートを items[at0000] で書く）を訂正後の path に写す（#38）。
      # 同じ gem path に複数の要素が写る場合は文書順で結ぶ
      corrected_path = by_gem_path.fetch(field["path"], [ field["path"] ])[gem_path_seen[field["path"]]] || field["path"]
      gem_path_seen[field["path"]] += 1
      constraint = constraints.fetch(corrected_path, { "alternatives" => [ field["rm_type"] ], "min_occurrences" => 0, "archetype_id" => field["archetype_id"], "units_list" => [ field["units"] ].compact })
      field = rewrite_embedded_field(field, corrected_path, constraint, entry, terms)
      instance_label = instance_terms.dig(field["node_id"], "text") if field["archetype_id"] == entry[:archetype_id]
      field["label"] = instance_label if instance_label.present?
      field_alternatives = constraint.fetch("alternatives")
      min_occurrences = constraint.fetch("min_occurrences")
      field.merge(
        "rm_type_alternatives" => field_alternatives,
        "input_kind" => Opt::InputKind.for(field, field_alternatives),
        "min_occurrences" => min_occurrences,
        "required" => field["required"] || min_occurrences >= 1,
        "units_list" => constraint.fetch("units_list", [])
      )
    end
    entry.merge(occurrences: interval_to_h(entry[:occurrences]), fields: fields).stringify_keys
  end

  def self.interval_to_h(interval)
    return nil unless interval

    { "lower" => interval.lower, "upper" => interval.upper }
  end
  private_class_method :build_web_template, :serialize_entry, :interval_to_h

  def entries
    (web_template || {})["entries"] || []
  end

  def fields
    entries.flat_map { |entry| entry["fields"] || [] }
  end
end
