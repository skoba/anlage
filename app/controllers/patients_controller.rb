# 患者（EHR）の一覧と作成（skoba/anlage#130、docs/design/m3-plan.md 7 節 P1）。
# 患者 = EHR 1 つ。EHR は gem のモデル（OpenehrRails::Rm::Ehr、openehr-rails 0.9.0 lib/openehr_rails/rm/ehr.rb）で、
# 作り方は gem の REST（openehr_api/ehrs_controller.rb:142 の Ehr.create!(… ehr_id: SecureRandom.uuid)）と同じ。
# 持つのは患者 ID（subject_id）と名前空間（subject_namespace）だけ。氏名などは持たない（計画書 7.2）
class PatientsController < ApplicationController
  SUBJECT_NAMESPACE = "anlage".freeze

  def index
    @patients = patients
    @subject_id = ""
  end

  def create
    @subject_id = params.dig(:patient, :subject_id).to_s.strip
    @error = creation_error(@subject_id)
    if @error
      @patients = patients
      return render :index, status: :unprocessable_content
    end

    ehr = OpenehrRails::Rm::Ehr.create!(ehr_id: SecureRandom.uuid, subject_id: @subject_id, subject_namespace: SUBJECT_NAMESPACE)
    redirect_to patient_path(ehr.ehr_id)
  end

  def show
    @patient = OpenehrRails::Rm::Ehr.find_by!(ehr_id: params[:id])
    # 結び付きは RM の側が権威（計画書 7.2）。原本（compositions）は uid で引く
    uids = OpenehrRails::Rm::Composition.latest.where(ehr: @patient).pluck(:uid)
    @compositions = Composition.includes(:template).where(uid: uids).order(created_at: :desc, id: :desc)
  end

  # いまの患者を選ぶ（skoba/anlage#134）。無い EHR は 404
  def select
    ehr = OpenehrRails::Rm::Ehr.find_by!(ehr_id: params[:id])
    session[:ehr_id] = ehr.ehr_id
    redirect_to patient_path(ehr.ehr_id)
  end

  def deselect
    session.delete(:ehr_id)
    redirect_to patients_path
  end

  private

  def patients
    OpenehrRails::Rm::Ehr.where.not(subject_id: nil).order(:subject_namespace, :subject_id)
  end

  def creation_error(subject_id)
    return "患者 ID を入力してください" if subject_id.blank?

    "この患者 ID はすでにあります" if OpenehrRails::Rm::Ehr.exists?(subject_id: subject_id, subject_namespace: SUBJECT_NAMESPACE)
  end
end
