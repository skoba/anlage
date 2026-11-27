require "rails_helper"

# 患者の画面の「この患者の記録を AQL で引く」（R-20261127-9 の作業列 3、openehr-rails 0.12.0 の #94）。
# 問いに EHR ID を入れた状態で AQL 照会の画面を開く。開いただけでは実行しない（実行は画面のボタン）。
# 文言は docs/demo/ui-vocabulary.md の写し
RSpec.describe "患者の画面から、この患者の記録を AQL で引く", type: :request do
  def document = Nokogiri::HTML(response.body)

  let!(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!) }

  def link_query(patient)
    get "/patients/#{patient.ehr_id}"
    link = document.at_css("a#patient_aql")
    expect(link.text).to eq("この患者の記録を AQL で引く")
    uri = URI(link["href"])
    expect(uri.path).to eq("/openehr/query")
    Rack::Utils.parse_query(uri.query)
  end

  it "リンクの問いは EHR ID を query_parameters の $ehr_id で受け、AQL 照会の入力欄に入った状態で開く" do
    patient = select_patient
    params = link_query(patient)
    expect(params["q"]).to include("FROM EHR e[ehr_id/value=$ehr_id] CONTAINS COMPOSITION c")
    expect(JSON.parse(params["query_parameters"])).to eq("ehr_id" => patient.ehr_id)

    get "/openehr/query", params: params
    expect(response).to have_http_status(:ok)
    expect(document.at_css("#aql-query").text).to eq(params["q"])
  end

  it "リンクの問いを実行すると、その患者の記録だけが返る（ほかの患者の記録は出ない）" do
    patient = select_patient
    %w[高血圧症 2型糖尿病].each do |name|
      post "/compositions/#{template.template_id}", params: { values: { "problem_diagnosis_at0002" => name } }
    end
    select_patient("SPEC-OTHER")
    post "/compositions/#{template.template_id}", params: { values: { "problem_diagnosis_at0002" => "喘息" } }

    params = link_query(patient)
    result = OpenehrRails::Aql.execute(params["q"], params: JSON.parse(params["query_parameters"]))

    expect(result.rows.size).to eq(2)
    expect(result.rows.map { _1[1] }).to all(eq("ProblemList"))
    uids = OpenehrRails::Rm::Composition.latest.where(ehr: patient).pluck(:uid)
    expect(result.rows.map(&:first)).to match_array(uids)
  end
end
