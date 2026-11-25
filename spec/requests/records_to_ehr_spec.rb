require "rails_helper"

# skoba/anlage#136（M3 の P3、docs/design/m3-plan.md 7 節）: 保存した記録を、いまの患者の EHR に結び付ける。
# 結び付きは RM の側（openehr_rm_compositions.ehr_id）を権威とする。anlage の compositions に列は足さない（計画書 7.2）
RSpec.describe "記録を EHR に結び付ける（#136）", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def document = Nokogiri::HTML(response.body)

  let!(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!) }
  let!(:patient) { OpenehrRails::Rm::Ehr.create!(ehr_id: SecureRandom.uuid, subject_id: "P-0001", subject_namespace: "anlage") }
  let!(:other) { OpenehrRails::Rm::Ehr.create!(ehr_id: SecureRandom.uuid, subject_id: "P-0002", subject_namespace: "anlage") }

  def save_problem(name)
    post "/compositions/#{template.template_id}", params: { values: { "problem_diagnosis_at0002" => name } }
    expect(response).to have_http_status(:found)
    Composition.order(:id).last
  end

  def rm_ehr_of(composition)
    OpenehrRails::Rm::Composition.latest.find_by!(uid: composition.uid).ehr
  end

  it "患者を選んで保存すると、RM の composition の EHR がその患者の EHR になる" do
    post "/patients/#{patient.ehr_id}/select"

    expect(rm_ehr_of(save_problem("高血圧症"))).to eq(patient)
  end

  it "患者を選んでいなければ、これまでどおり EHR に結び付けない" do
    expect(rm_ehr_of(save_problem("高血圧症"))).to be_nil
  end

  it "患者の画面に、その患者の記録が新しい順に出る（ほかの患者・未割り当ての記録は出ない）" do
    save_problem("未割り当て")
    post "/patients/#{other.ehr_id}/select"
    save_problem("ほかの患者")
    post "/patients/#{patient.ehr_id}/select"
    first = travel_to(1.minute.from_now) { save_problem("高血圧症") }
    second = travel_to(2.minutes.from_now) { save_problem("糖尿病") }

    get "/patients/#{patient.ehr_id}"

    expect(document.at_css("h2").text).to eq("カルテ記録")
    expect(document.css("ul.patient-records a").map { _1["href"] }).to eq([ "/compositions/#{second.id}", "/compositions/#{first.id}" ])
  end

  it "記録が無ければ、患者の画面に「この患者のカルテ記録はまだありません。」と出る" do
    get "/patients/#{patient.ehr_id}"

    expect(response.body).to include("この患者のカルテ記録はまだありません。")
  end

  it "AQL の FROM EHR e[ehr_id/value='…'] で、その患者の記録だけが引ける" do
    post "/patients/#{patient.ehr_id}/select"
    save_problem("高血圧症")
    post "/patients/#{other.ehr_id}/select"
    save_problem("糖尿病")

    result = OpenehrRails::Aql::Executor.execute(<<~AQL)
      SELECT e/ehr_id/value, ev/data[at0001]/items[at0002]/value/value
      FROM EHR e[ehr_id/value='#{patient.ehr_id}'] CONTAINS COMPOSITION c CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
    AQL
    expect(result.rows).to eq([ [ patient.ehr_id, "高血圧症" ] ])
  end
end
