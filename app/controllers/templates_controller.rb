class TemplatesController < ApplicationController
  include ActionView::RecordIdentifier

  MAX_UPLOAD_SIZE = 5.megabytes
  ALLOWED_EXTENSIONS = /\.(opt|xml)\z/i

  # CKM (Clinical Knowledge Manager) is the only external source this
  # demo trusts to fetch OPTs from server-side; RemoteFetcher's own
  # private/loopback/link-local IP blocking guards the fetch itself,
  # this is an additional, stricter allowlist on top of it.
  ALLOWED_URL_HOSTS = %w[ckm.openehr.org].freeze

  def index
    @templates = Template.active.order(:template_id)
  end

  # Parses and validates an uploaded OPT without persisting it (the
  # "fitting room"): summary + a live form preview, so the visitor can
  # inspect the template before deciding to register it.
  def preview
    content = read_validated_content || return
    return unless (@template = parse_upload(content))

    @existing = Template.find_by_checksum(content)
    unless @existing
      @superseding = Template.active.find_by(template_id: @template.template_id)
      @diff = Opt::TemplateDiff.call(@superseding, @template) if @superseding
    end

    respond_to do |format|
      format.html { render :preview, layout: false }
      format.json do
        render json: {
          template_id: @template.template_id,
          concept: @template.web_template["concept"],
          archetype_count: @template.entries.size,
          field_count: @template.fields.size,
          already_registered: @existing.present?,
          new_version_of: @superseding&.template_id
        }
      end
    end
  end

  # Registers the template (idempotent by checksum) and appends its card
  # to the catalog via a Turbo Stream, so the drop-to-register flow never
  # needs a full page reload.
  def create
    content = read_validated_content || return

    if (existing = Template.find_by_checksum(content))
      return render_notice("already registered as #{existing.template_id} (v#{existing.version})")
    end

    return unless (template = parse_upload(content))

    superseding = Template.active.find_by(template_id: template.template_id)
    template.version = Template.next_version(superseding.version) if superseding

    if template.save
      superseding&.supersede!

      respond_to do |format|
        format.turbo_stream do
          streams = [ turbo_stream.append("catalog", partial: "templates/template", locals: { template: template }) ]
          streams << turbo_stream.remove("empty_notice") unless superseding
          streams << turbo_stream.remove(dom_id(superseding)) if superseding
          render turbo_stream: streams
        end
        format.json { render json: { template_id: template.template_id, version: template.version, name: template.web_template["concept"] }, status: :created }
      end
    else
      render_upload_error(template.errors.full_messages.join(", "))
    end
  end

  private

  def read_validated_content
    return read_validated_url if params[:url].present?

    read_validated_upload
  end

  def read_validated_upload
    file = params[:file]
    unless file
      render_upload_error("no file given")
      return nil
    end
    if file.size > MAX_UPLOAD_SIZE
      render_upload_error("file exceeds the 5MB limit")
      return nil
    end
    unless file.original_filename.to_s.match?(ALLOWED_EXTENSIONS)
      render_upload_error("only .opt or .xml files are supported")
      return nil
    end

    file.read.force_encoding(Encoding::UTF_8)
  end

  # Fetches an OPT from an allowlisted URL server-side, via
  # OpenehrRails::Opt::RemoteFetcher (blocks private/loopback/link-local
  # targets, caps redirects and response size). The fetched body still
  # goes through parse_upload -> Opt::SafeParser afterwards, same as an
  # uploaded file, since RemoteFetcher's own validation doesn't guard
  # against XXE.
  def read_validated_url
    url = params[:url].to_s
    host = begin
      URI.parse(url).host
    rescue URI::InvalidURIError
      nil
    end

    unless host && ALLOWED_URL_HOSTS.include?(host)
      render_upload_error("only URLs on #{ALLOWED_URL_HOSTS.join(', ')} are supported")
      return nil
    end

    content = OpenehrRails::Opt::RemoteFetcher.fetch(url).force_encoding(Encoding::UTF_8)
    if content.bytesize > MAX_UPLOAD_SIZE
      render_upload_error("file exceeds the 5MB limit")
      return nil
    end

    content
  rescue OpenehrRails::Opt::RemoteFetcher::FetchError => e
    render_upload_error(e.message)
    nil
  end

  def parse_upload(content)
    Template.build_from_opt_xml(content)
  rescue Opt::UnsafeTemplate, Template::InvalidTemplate => e
    render_upload_error(e.message)
    nil
  end

  def render_upload_error(message)
    respond_to do |format|
      format.html { render plain: message, status: :unprocessable_content }
      format.json { render json: { error: message }, status: :unprocessable_content }
      format.turbo_stream { render turbo_stream: turbo_stream.update("upload_status", message), status: :unprocessable_content }
    end
  end

  def render_notice(message)
    respond_to do |format|
      format.html { render plain: message, status: :ok }
      format.json { render json: { notice: message }, status: :ok }
      format.turbo_stream { render turbo_stream: turbo_stream.update("upload_status", message), status: :ok }
    end
  end
end
