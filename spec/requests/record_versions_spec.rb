require "rails_helper"

# skoba/anlage#138（M3 の P4、docs/design/m3-plan.md 7 節）: カルテ記録の修正と版。
# 修正は同じ uid で commit し、RM の側に版が 1 つ足される（gem の committer が前の head の latest_version を下ろす）。
# 原本（compositions）は版ごとに 1 行。一覧には各記録の新しい版だけを出す。文言は docs/demo/ui-vocabulary.md の「カルテ記録」の行
RSpec.describe "カルテ記録の修正と版（#138）", type: :request do
  def document = Nokogiri::HTML(response.body)

  let!(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!) }

  def save_problem(name)
    post "/compositions/#{template.template_id}", params: { values: { "problem_diagnosis_at0002" => name } }
    Composition.order(:id).last
  end

  def edit_problem(composition, name)
    patch "/compositions/#{composition.id}", params: { values: { "problem_diagnosis_at0002" => name } }
  end

  it "記録の画面に「修正」が出て、修正の帳票には前の版の値が入っている" do
    first = save_problem("高血圧症")

    get "/compositions/#{first.id}"
    expect(document.at_css("a#edit_composition")["href"]).to eq("/compositions/#{first.id}/edit")

    get "/compositions/#{first.id}/edit"
    expect(response).to have_http_status(:ok)
    form = document.at_css("form[action='/compositions/#{first.id}']")
    expect(form.at_css("input[name='_method']")["value"]).to eq("patch")
    expect(form.at_css("input[name='values[problem_diagnosis_at0002]']")["value"]).to eq("高血圧症")
  end

  it "修正すると、同じ uid の 2 版めができ、新しい版の画面に移る" do
    first = save_problem("高血圧症")

    expect { edit_problem(first, "本態性高血圧症") }.to change(Composition, :count).by(1)

    second = Composition.order(:id).last
    expect(second.uid).to eq(first.uid)
    expect(response).to redirect_to("/compositions/#{second.id}")
    expect(OpenehrRails::Rm::Version.of_object(first.uid).pluck(:version_tree_id)).to eq(%w[1 2])
    head = OpenehrRails::Rm::Composition.latest.find_by!(uid: first.uid)
    expect(head.version.version_tree_id).to eq("2")

    follow_redirect!
    expect(response.body).to include("修正しました")
  end

  it "カルテ記録一覧には、各記録の新しい版だけが出る" do
    first = save_problem("高血圧症")
    other = save_problem("糖尿病")
    edit_problem(first, "本態性高血圧症")
    second = Composition.order(:id).last

    get "/compositions"

    expect(document.css("main a").map { _1["href"] }).to contain_exactly("/compositions/#{second.id}", "/compositions/#{other.id}")
  end

  it "記録の画面に版の履歴が出て、置き換えられた版には「修正」を出さない" do
    first = save_problem("高血圧症")
    edit_problem(first, "本態性高血圧症")
    second = Composition.order(:id).last

    get "/compositions/#{second.id}"
    expect(document.at_css("h2#version_history").text).to eq("版の履歴")
    expect(document.css("ol.versions li").map { _1.text.squish }).to match([ /\A版 1（.+）\z/, /\A版 2（.+）（この版）\z/ ])
    expect(document.css("ol.versions li a").map { _1["href"] }).to eq([ "/compositions/#{first.id}" ])

    get "/compositions/#{first.id}"
    expect(response.body).to include("この版は置き換えられています。")
    expect(document.at_css("a#latest_version")["href"]).to eq("/compositions/#{second.id}")
    expect(document.at_css("a#edit_composition")).to be_nil

    get "/compositions/#{first.id}/edit"
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "修正の値が不正なら 422 で、版は増えない" do
    first = save_problem("高血圧症")

    expect { patch "/compositions/#{first.id}", params: { values: { "problem_diagnosis_at0002" => "", "problem_diagnosis_at0077" => "2026-09-25T00:00:00" } } }
      .not_to change(Composition, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("必須項目です")
    expect(OpenehrRails::Rm::Version.of_object(first.uid).count).to eq(1)
  end

  it "修正しても、記録の EHR は変わらない（いまの患者を変えていても）" do
    patient = OpenehrRails::Rm::Ehr.create!(ehr_id: SecureRandom.uuid, subject_id: "P-0001", subject_namespace: "anlage")
    post "/patients/#{patient.ehr_id}/select"
    first = save_problem("高血圧症")
    delete "/patients/selection"

    edit_problem(first, "本態性高血圧症")

    expect(OpenehrRails::Rm::Composition.latest.find_by!(uid: first.uid).ehr).to eq(patient)
  end

  it "読み戻せない形を含む記録（jp_referral）には「修正」を出さず、修正の帳票も開けない（422）" do
    referral = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/jp_referral.opt").read).tap(&:save!)
    post "/compositions/#{referral.template_id}", params: { values: { "service_request_at0121" => "精査依頼", "problem_diagnosis_at0002" => "2型糖尿病" } }
    composition = Composition.order(:id).last

    get "/compositions/#{composition.id}"
    expect(document.at_css("a#edit_composition")).to be_nil
    expect(response.body).to include("この記録は修正できません")

    get "/compositions/#{composition.id}/edit"
    expect(response).to have_http_status(:unprocessable_content)
  end
end

# 単位が 2 つ以上ある数量（bmi_calculation の BMI: kg/m2 と [lb_av]/[in_i]2）は、修正の帳票で前の版の単位を選んでおく
RSpec.describe "修正の帳票の単位（#138）", type: :request do
  it "前の版の単位が選ばれている" do
    bmi = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/bmi_calculation.opt").read).tap(&:save!)
    post "/compositions/#{bmi.template_id}", params: { values: { "body_mass_index" => "500", "body_mass_index__units" => "[lb_av]/[in_i]2" } }
    composition = Composition.order(:id).last

    get "/compositions/#{composition.id}/edit"

    selected = Nokogiri::HTML(response.body).at_css("select[name='values[body_mass_index__units]'] option[selected]")
    expect(selected&.[]("value")).to eq("[lb_av]/[in_i]2")
  end
end
