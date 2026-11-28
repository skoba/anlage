require "rails_helper"

# 下書きの試しの表示（?preview=）と、帳票の保存のあと then に進む（via の印）。
# docs/design/definition-registration-plan.md 1.1 節・6 節・10 節、skoba/anlage#294、R-20261128-7。
# 組は spec/fixtures/definitions/clinic（lab_entry の画面に、保存のあと patient_chart に戻るボタン save_and_back がある）
RSpec.describe "定義の組の試しの表示と、保存のあとの then", type: :request do
  let(:fixture) { Rails.root.join("spec/fixtures/definitions/clinic") }
  let(:ehr) { OpenehrRails::Rm::Ehr.find_by!(subject_id: "DEMO-01") }
  let(:lab_values) do
    { "laboratory_test_result_at0005" => "血液検査", "laboratory_test_analyte_at0024" => "試験項目甲",
      "laboratory_test_analyte_at0001" => "3.5", "laboratory_test_analyte_at0001__units" => "mmol/L" }
  end

  around do |example|
    original = ENV["ANLAGE_DEFINITION_BUNDLE"]
    ENV["ANLAGE_DEFINITION_BUNDLE"] = "clinic_spec"
    example.run
  ensure
    original ? ENV["ANLAGE_DEFINITION_BUNDLE"] = original : ENV.delete("ANLAGE_DEFINITION_BUNDLE")
  end

  before { Evaluation::Datasets.build("demo_initial") }

  def document = Nokogiri::HTML(response.body)
  def screen = document.at_css("[data-definition-screen]")&.[]("data-definition-screen")
  def notice = document.at_css("#definition_notice")&.text&.squish
  def button_href(id) = document.at_css("[data-definition-button='#{id}']")["href"]
  def register = DefinitionBundle.register(Definitions::Files.read(fixture), registered_by: "rake").bundle

  describe "?preview=" do
    it "下書きは、?preview= を付けたときだけ使う。画面の上に、試しの表示であることと、保存は本当に保存されることを出す" do
      draft = register

      get patient_path(ehr.ehr_id)
      expect(screen).to eq("builtin 1.0.0 patient_chart")

      get patient_path(ehr.ehr_id, preview: draft.id)
      expect(screen).to eq("clinic_spec 0.1.0 patient_chart")
      expect(notice).to eq("下書き clinic_spec 0.1.0 を試しに表示しています。ここから開いた帳票で保存すると、本当に保存されます。")
      expect(draft.reload.status).to eq("draft")
    end

    it "動いている画面は、下書きを試しても変わらない（印の無い URL は、動いている版のまま）" do
      register.activate!
      dir = Pathname(Dir.mktmpdir).join("clinic").tap { FileUtils.cp_r(fixture, _1) }
      dir.join("bundle.yml").write(dir.join("bundle.yml").read.sub(/^version: .*$/, "version: 0.2.0"))
      draft = DefinitionBundle.register(Definitions::Files.read(dir), registered_by: "rake").bundle

      get patient_path(ehr.ehr_id, preview: draft.id)
      expect(screen).to eq("clinic_spec 0.2.0 patient_chart")

      get patient_path(ehr.ehr_id)
      expect(screen).to eq("clinic_spec 0.1.0 patient_chart")
      expect(notice).to be_nil
    ensure
      FileUtils.remove_entry(dir.dirname) if dir
    end

    it "下書きでない行や、無い行の id は試さない。動いている画面と、理由の文" do
      active = register.tap(&:activate!)

      [ active.id, 0 ].each do |id|
        get patient_path(ehr.ehr_id, preview: id)
        expect(screen).to eq("clinic_spec 0.1.0 patient_chart")
        expect(notice).to eq("試しに表示する下書き（#{id}）がありません。動いている画面を出しています。")
      end
    end

    it "試しの表示の中のボタン（open.screen）は、試しの表示のまま、ほかの画面に移る" do
      draft = register

      get patient_path(ehr.ehr_id, preview: draft.id)
      get button_href("enter_lab")

      expect(screen).to eq("clinic_spec 0.1.0 lab_entry")
    end
  end

  describe "via の印と then" do
    before { post select_patient_path(ehr.ehr_id) }

    it "ボタンの open.form は、帳票の URL に via の印を付ける。保存のあと、組の行からボタンを引き直して then の画面に移る" do
      bundle = register.tap(&:activate!)
      get patient_path(ehr.ehr_id, screen: "lab_entry")
      href = button_href("save_and_back")
      expect(href).to eq(form_path("LabResultReport", via: "#{bundle.id}.save_and_back"))

      get href
      expect(document.at_css("input[name='via']")["value"]).to eq("#{bundle.id}.save_and_back")

      post template_compositions_path("LabResultReport"), params: { values: lab_values, via: "#{bundle.id}.save_and_back" }
      expect(response).to redirect_to(patient_path(ehr.ehr_id, screen: "patient_chart"))
    end

    it "試しの表示から開いた帳票は、本当に保存され、then の画面も試しの表示のまま" do
      draft = register

      expect do
        post template_compositions_path("LabResultReport"), params: { values: lab_values, via: "#{draft.id}.save_and_back" }
      end.to change(Composition, :count).by(1)
      expect(response).to redirect_to(patient_path(ehr.ehr_id, screen: "patient_chart", preview: draft.id))
    end

    it "印が引けないとき（無い行、無いボタン、then の無いボタン、ほかの帳票のボタン、形の違う印）は、いまと同じ記録の画面に移る。移る先を URL から取らない" do
      bundle = register.tap(&:activate!)
      tokens = [ "0.save_and_back", "#{bundle.id}.no_such_button", "#{bundle.id}.enter_lab", "#{bundle.id}", "https://example.com/" ]

      tokens.each do |token|
        post template_compositions_path("LabResultReport"), params: { values: lab_values, via: token }
        expect(response).to redirect_to(composition_path(Composition.order(:id).last)), token
      end
      post template_compositions_path("ProblemList"), params: { values: { "problem_diagnosis_at0002" => "高血圧症" }, via: "#{bundle.id}.save_and_back" }
      expect(response).to redirect_to(composition_path(Composition.order(:id).last))
    end
  end
end
