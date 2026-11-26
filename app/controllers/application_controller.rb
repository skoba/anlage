class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_ehr

  private

  # いまの患者の EHR（skoba/anlage#134・#136）。選んでいないか、EHR が無くなっていれば nil
  def current_ehr
    return @current_ehr if defined?(@current_ehr)

    @current_ehr = session[:ehr_id] && OpenehrRails::Rm::Ehr.find_by(ehr_id: session[:ehr_id])
  end
end
