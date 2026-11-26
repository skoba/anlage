require "rails_helper"

# 患者を選ばないと、カルテ記録を保存できない（skoba/anlage#161、R-20261126-2 の 5。M3 の計画書 7.5 節の問い 4）。
# openEHR では、記録は必ず EHR に属する。修正（同じ記録の新しい版）は元の EHR のままで、いまの選択に依らない。
# 文言は docs/demo/ui-vocabulary.md の「帳票」の行の写し。
RSpec.describe "患者を選ばないと保存できない（#161）", type: :request do
  let!(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!) }

  def document = Nokogiri::HTML(response.body)

  it "選んでいなければ、帳票に注記と「患者」へのリンクが出て、保存のボタンが出ない" do
    get "/forms/#{template.template_id}"

    notice = document.at_css("#patient_required")
    expect(notice.text.squish).to eq("患者を選んでいません。保存するには、先に患者を選んでください。")
    expect(notice.at_css("a")).to have_attributes(text: "患者", attributes: include("href" => have_attributes(value: "/patients")))
    expect(document.css("form[action^='/compositions'] button[type=submit]")).to be_empty
  end

  it "選ばずに保存しようとすると 422 で、帳票のエラーが出る。記録は増えない" do
    expect { post "/compositions/#{template.template_id}", params: { values: { "problem_diagnosis_at0002" => "高血圧症" } } }
      .not_to change { [ Composition.count, OpenehrRails::Rm::Composition.count ] }

    expect(response).to have_http_status(:unprocessable_content)
    expect(document.at_css("p.form-error").text).to eq("患者を選んでいません。患者を選んでから保存してください")
  end

  it "選んでいれば、注記は出ず、保存のボタンが出て、その患者の EHR に保存される" do
    patient = select_patient

    get "/forms/#{template.template_id}"
    expect(document.at_css("#patient_required")).to be_nil
    expect(document.css("form[action^='/compositions'] button[type=submit]").map(&:text)).to eq([ "保存" ])

    post "/compositions/#{template.template_id}", params: { values: { "problem_diagnosis_at0002" => "高血圧症" } }
    expect(response).to have_http_status(:redirect)
    expect(OpenehrRails::Rm::Composition.latest.find_by!(uid: Composition.last.uid).ehr).to eq(patient)
  end

  it "修正は、選択を外したあとでもでき、元の EHR のまま" do
    patient = select_patient
    post "/compositions/#{template.template_id}", params: { values: { "problem_diagnosis_at0002" => "高血圧症" } }
    composition = Composition.last
    delete "/patients/selection"

    get "/compositions/#{composition.id}/edit"
    expect(document.at_css("#patient_required")).to be_nil
    patch "/compositions/#{composition.id}", params: { values: { "problem_diagnosis_at0002" => "本態性高血圧症" } }

    expect(response).to have_http_status(:redirect)
    expect(OpenehrRails::Rm::Composition.latest.find_by!(uid: composition.uid).ehr).to eq(patient)
  end
end
