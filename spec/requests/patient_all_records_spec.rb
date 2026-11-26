require "rails_helper"

# skoba/anlage#182（R-20261126-7、docs/design/m3-plan.md 8 節）: 患者の画面に、EHR に入っている記録をすべて出す。
# テンプレートが未登録の記録（RM の側にだけある。初期データの紹介状と同じ入れ方）は、閲覧だけの画面へ。
# 行は記録日（context/start_time）の新しい順で、記録日を出す（既知の制限 12a・12b）
RSpec.describe "患者の画面の、すべての記録（#182）", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def document = Nokogiri::HTML(response.body)

  JST = ActiveSupport::TimeZone["Asia/Tokyo"]

  let!(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!) }
  let!(:patient) { spec_patient }

  def save_problem(name)
    select_patient
    post "/compositions/#{template.template_id}", params: { values: { "problem_diagnosis_at0002" => name } }
    expect(response).to have_http_status(:found)
    Composition.order(:id).last
  end

  # テンプレートを登録していない紹介状（jp_referral の構造骨格 fixture）を、RM の側にだけ入れる（Demo::SampleCompositions と同じ経路）
  def commit_referral(ehr: patient, recorded_at: JST.parse("2026-05-12 09:00"))
    canonical = JSON.parse(Rails.root.join("spec/fixtures/compositions/jp_referral/skeleton.canonical.json").read)
    OpenehrRails::Rm::CompositionCommitter.commit(canonical, uid: SecureRandom.uuid, ehr: ehr, owner: nil,
                                                             context_start_time: recorded_at)
  end

  def rows = document.css("ul.patient-records li")

  it "テンプレートが未登録の記録も出る。テンプレートの ID と記録日を出し、閲覧の画面へリンクする" do
    referral = commit_referral

    get "/patients/#{patient.ehr_id}"

    expect(rows.map { _1.text.strip }).to eq([ "jp_referral — 記録日 2026-05-12" ])
    expect(rows.first.at_css("a")["href"]).to eq("/patients/#{patient.ehr_id}/records/#{referral.uid}")
  end

  it "記録は記録日の新しい順に並び、行に記録日を出す（作った順ではない）" do
    referral = commit_referral(recorded_at: JST.parse("2026-05-12 09:00"))
    composition = travel_to(JST.parse("2026-11-26 10:30")) { save_problem("高血圧症") }
    older = commit_referral(recorded_at: JST.parse("2026-01-08 09:00"))

    get "/patients/#{patient.ehr_id}"

    expect(rows.map { _1.text.strip }).to eq([ "ProblemList — 記録日 2026-11-26", "jp_referral — 記録日 2026-05-12",
                                                "jp_referral — 記録日 2026-01-08" ])
    expect(rows.map { _1.at_css("a")["href"] }).to eq([ "/compositions/#{composition.id}",
                                                       "/patients/#{patient.ehr_id}/records/#{referral.uid}",
                                                       "/patients/#{patient.ehr_id}/records/#{older.uid}" ])
  end

  it "閲覧の画面に、記録の項目の名前と値と、テンプレートが未登録である注記を出す。修正・削除は出さない" do
    referral = commit_referral

    get "/patients/#{patient.ehr_id}/records/#{referral.uid}"

    expect(response).to have_http_status(:ok)
    expect(document.at_css("h1").text).to eq("カルテ記録: jp_referral")
    expect(response.body).to include("この記録のテンプレートは登録されていません。閲覧だけです。")
    expect(document.css("dl.record-summary dd").map(&:text)).to eq([ "jp_referral", "2026-05-12" ])
    items = document.css("table.record-items tbody tr").map { |row| row.css("td").map { _1.text.strip } }
    expect(items).to include([ "サービス名", "外来紹介" ], [ "名称", "X病院" ], [ "プロブレム・診断の名称", "2型糖尿病" ])
    expect(document.at_css("details summary").text).to eq("canonical JSON")
    expect(document.at_css("a#edit_composition")).to be_nil
    expect(document.css("form button").map(&:text)).not_to include("削除")
  end

  # 受け入れの台本 C2（docs/demo/acceptance-v0.2.0.md）の裏付け
  it "初期データの DEMO-01 の画面に、紹介状を含む 18 件が記録日の新しい順に出る" do
    Rake::Task["demo:reset"].reenable
    Rake::Task["demo:reset"].invoke
    demo01 = OpenehrRails::Rm::Ehr.find_by!(subject_id: "DEMO-01")

    get "/patients/#{demo01.ehr_id}"

    texts = rows.map { _1.text.strip }
    expect(texts.size).to eq(18)
    expect(texts.first).to eq("CardiologyEncounter — 記録日 2026-10-15")
    expect(texts).to include("jp_referral — 記録日 2026-08-03")
    expect(texts.map { _1[/\d{4}-\d{2}-\d{2}/] }).to eq(texts.map { _1[/\d{4}-\d{2}-\d{2}/] }.sort.reverse)
  end

  it "ほかの患者の記録と、削除済みの記録の閲覧は 404" do
    other = spec_patient("SPEC-OTHER")
    others = commit_referral(ehr: other)
    deleted = commit_referral
    OpenehrRails::Rm::CompositionCommitter.delete(uid: deleted.uid, ehr: patient)

    get "/patients/#{patient.ehr_id}/records/#{others.uid}"
    expect(response).to have_http_status(:not_found)
    get "/patients/#{patient.ehr_id}/records/#{deleted.uid}"
    expect(response).to have_http_status(:not_found)

    get "/patients/#{patient.ehr_id}"
    expect(rows).to be_empty
  end
end
