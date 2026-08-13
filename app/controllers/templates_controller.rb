class TemplatesController < ApplicationController
  MAX_UPLOAD_SIZE = 5.megabytes
  ALLOWED_EXTENSIONS = /\.(opt|xml)\z/i

  def index
    @templates = Template.active.order(:template_id)
  end

  # Parses and validates an uploaded OPT without persisting it (the
  # "fitting room"): summary + a live form preview, so the visitor can
  # inspect the template before deciding to register it.
  def preview
    content = read_validated_upload || return
    return unless (@template = parse_upload(content))

    @existing = Template.find_by_checksum(content)

    respond_to do |format|
      format.html { render :preview, layout: false }
      format.json do
        render json: {
          template_id: @template.template_id,
          concept: @template.web_template["concept"],
          archetype_count: @template.entries.size,
          field_count: @template.fields.size,
          already_registered: @existing.present?
        }
      end
    end
  end

  # Registers the template (idempotent by checksum) and appends its card
  # to the catalog via a Turbo Stream, so the drop-to-register flow never
  # needs a full page reload.
  def create
    content = read_validated_upload || return

    if (existing = Template.find_by_checksum(content))
      return render_notice("already registered as #{existing.template_id} (v#{existing.version})")
    end

    return unless (template = parse_upload(content))

    if template.save
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.append("catalog", partial: "templates/template", locals: { template: template }) }
        format.json { render json: { template_id: template.template_id, name: template.web_template["concept"] }, status: :created }
      end
    else
      render_upload_error(template.errors.full_messages.join(", "))
    end
  end

  private

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
