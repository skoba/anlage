require "rails_helper"

# skoba/anlage#140（M3 の P5、docs/design/m3-plan.md 7 節）: カルテ記録の削除は利用者の操作で、論理削除。
# gem の REST の DELETE（openehr-rails 0.9.0 openehr_api/compositions_controller.rb:57-65）と同じく、
# head を同じ uid で commit し直して、その版の lifecycle を 523（deleted）にする。行（原本・RM）は消さない。
# 文言は docs/demo/ui-vocabulary.md の「カルテ記録」の行
RSpec::Matchers.define_negated_matcher :not_change, :change

RSpec.describe "カルテ記録の削除（#140）", type: :request do
  def document = Nokogiri::HTML(response.body)

  let!(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!) }
  let!(:patient) { OpenehrRails::Rm::Ehr.create!(ehr_id: SecureRandom.uuid, subject_id: "P-0001", subject_namespace: "anlage") }

  def save_problem(name)
    post "/compositions/#{template.template_id}", params: { values: { "problem_diagnosis_at0002" => name } }
    Composition.order(:id).last
  end

  it "記録の画面に「削除」が出る" do
    composition = save_problem("高血圧症")

    get "/compositions/#{composition.id}"

    expect(document.at_css("form[action='/compositions/#{composition.id}'] input[name='_method'][value='delete']")).to be_present
    expect(document.at_css("form[action='/compositions/#{composition.id}'] button").text).to eq("削除")
  end

  it "削除すると、削除の版（lifecycle 523）ができ、行は消えずに、一覧と患者の画面から消える" do
    post "/patients/#{patient.ehr_id}/select"
    deleted = save_problem("高血圧症")
    kept = save_problem("糖尿病")

    expect { delete "/compositions/#{deleted.id}" }
      .to not_change(Composition, :count).and change(OpenehrRails::Rm::Composition, :count).by(1)
    expect(response).to redirect_to("/compositions")
    follow_redirect!
    expect(response.body).to include("削除しました")

    versions = OpenehrRails::Rm::Version.of_object(deleted.uid)
    expect(versions.map { [ _1.version_tree_id, _1.lifecycle_state_code ] }).to eq([ %w[1 532], %w[2 523] ])
    expect(OpenehrRails::Rm::Composition.latest.find_by!(uid: deleted.uid).ehr).to eq(patient)

    expect(document.css("main a").map { _1["href"] }).to eq([ "/compositions/#{kept.id}" ])

    get "/patients/#{patient.ehr_id}"
    expect(document.css("ul.patient-records a").map { _1["href"] }).to eq([ "/compositions/#{kept.id}" ])
  end

  it "削除済みの記録の画面は「削除済み」と出し、修正・削除を出さない。修正も削除も 422" do
    composition = save_problem("高血圧症")
    delete "/compositions/#{composition.id}"

    get "/compositions/#{composition.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("このカルテ記録は削除済みです。")
    expect(document.at_css("a#edit_composition")).to be_nil
    expect(document.at_css("input[name='_method'][value='delete']")).to be_nil

    get "/compositions/#{composition.id}/edit"
    expect(response).to have_http_status(:unprocessable_content)
    patch "/compositions/#{composition.id}", params: { values: { "problem_diagnosis_at0002" => "x" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect { delete "/compositions/#{composition.id}" }.not_to change(OpenehrRails::Rm::Composition, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "置き換えられた版の画面からは削除できない（422）" do
    first = save_problem("高血圧症")
    patch "/compositions/#{first.id}", params: { values: { "problem_diagnosis_at0002" => "本態性高血圧症" } }

    expect { delete "/compositions/#{first.id}" }.not_to change(OpenehrRails::Rm::Composition, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end
end
