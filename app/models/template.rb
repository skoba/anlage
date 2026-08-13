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

  def self.build_web_template(opt, extractor)
    {
      "template_id" => opt.template_id.value,
      "concept" => opt.concept,
      "entries" => extractor.entries.map { |entry| serialize_entry(entry) }
    }
  end

  def self.serialize_entry(entry)
    entry.merge(occurrences: interval_to_h(entry[:occurrences])).stringify_keys
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
