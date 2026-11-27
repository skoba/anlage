require "rails_helper"

# 患者の画面の EHR ID を写すボタン（skoba/anlage#192、R-20261127-1 の 2、docs/design/m3-plan.md 9.2）。
# 受け入れの台本 H5 で、EHR ID を AQL に貼る操作に使う。文言は docs/demo/ui-vocabulary.md の写し。
RSpec.describe "患者の画面の EHR ID を写す（実ブラウザ）", type: :system, js: true do
  let!(:patient) do
    OpenehrRails::Rm::Ehr.create!(ehr_id: SecureRandom.uuid, subject_id: "DEMO-01",
                                  subject_namespace: PatientsController::SUBJECT_NAMESPACE)
  end

  # headless Chrome でクリップボードを読むための権限（CDP）
  before do
    page.driver.browser.execute_cdp("Browser.grantPermissions",
                                    permissions: %w[clipboardReadWrite clipboardSanitizedWrite],
                                    origin: Capybara.current_session.server.base_url)
  end

  it "「EHR ID を写す」を押すと、クリップボードに EHR ID が入り、「写しました」が出る" do
    visit patient_path(patient.ehr_id)

    click_button "EHR ID を写す"

    expect(page).to have_css(".copy-status", text: "写しました")
    copied = page.evaluate_async_script("navigator.clipboard.readText().then(arguments[0])")
    expect(copied).to eq(patient.ehr_id)
  end
end
