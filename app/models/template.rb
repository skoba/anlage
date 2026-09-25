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
    alternatives = Opt::ValueAlternatives.call(opt)
    {
      "template_id" => opt.template_id.value,
      "concept" => opt.concept,
      "entries" => extractor.entries.map { |entry| serialize_entry(entry, alternatives) }
    }
  end

  # gem の field に Anlage 側の 2 キーを additive に足す（skoba/anlage#33）:
  #   rm_type_alternatives: value 属性の代替 RM 型（OPT 出現順）
  #   input_kind: フォーム入力の方針属性（Opt::InputKind、登録時に一度だけ導出）
  def self.serialize_entry(entry, alternatives)
    fields = (entry[:fields] || []).map do |field|
      field = field.stringify_keys
      field_alternatives = alternatives.fetch(field["path"], [ field["rm_type"] ])
      field.merge(
        "rm_type_alternatives" => field_alternatives,
        "input_kind" => Opt::InputKind.for(field, field_alternatives)
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
