# いまの患者を選ぶ（skoba/anlage#161: 患者を選ばないと保存できない）。記録を保存する spec の前提。
# 患者は架空の ID（既定 SPEC-PATIENT）。同じ ID なら同じ EHR を使う。
module PatientSelectionHelpers
  SUBJECT_ID = "SPEC-PATIENT".freeze

  def spec_patient(subject_id = SUBJECT_ID)
    OpenehrRails::Rm::Ehr.find_or_create_by!(subject_id: subject_id, subject_namespace: PatientsController::SUBJECT_NAMESPACE) do |ehr|
      ehr.ehr_id = SecureRandom.uuid
    end
  end

  # request spec: セッションに選ぶ（POST /patients/:id/select）
  def select_patient(subject_id = SUBJECT_ID)
    spec_patient(subject_id).tap { |ehr| post "/patients/#{ehr.ehr_id}/select" }
  end

  # system spec: 患者の画面で「この患者を選ぶ」を押す
  def select_patient_in_browser(subject_id = SUBJECT_ID)
    spec_patient(subject_id).tap do |ehr|
      visit "/patients/#{ehr.ehr_id}"
      click_button "この患者を選ぶ"
      expect(page).to have_css("#current_patient", text: subject_id)
    end
  end
end

RSpec.configure do |config|
  config.include PatientSelectionHelpers, type: :request
  config.include PatientSelectionHelpers, type: :system
end
