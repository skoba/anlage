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
    file = params[:file]
    return render_upload_error("no file given") unless file

    return render_upload_error("file exceeds the 5MB limit") if file.size > MAX_UPLOAD_SIZE

    unless file.original_filename.to_s.match?(ALLOWED_EXTENSIONS)
      return render_upload_error("only .opt or .xml files are supported")
    end

    content = file.read

    begin
      @template = Template.build_from_opt_xml(content)
    rescue Opt::UnsafeTemplate, Template::InvalidTemplate => e
      return render_upload_error(e.message)
    end

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

  private

  def render_upload_error(message)
    respond_to do |format|
      format.html { render plain: message, status: :unprocessable_content }
      format.json { render json: { error: message }, status: :unprocessable_content }
    end
  end
end
