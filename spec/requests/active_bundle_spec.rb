require "rails_helper"

# 動かす組で患者の画面を出す（docs/design/definition-registration-plan.md 2 節・3 節・10 節、skoba/anlage#283、R-20261128-7 の回答 2・3）。
# 組は spec/fixtures/definitions/clinic（初期データのテンプレートの field だけを引く）
RSpec.describe "動かす定義の組（ANLAGE_DEFINITION_BUNDLE）", type: :request do
  let(:fixture) { Rails.root.join("spec/fixtures/definitions/clinic") }

  around do |example|
    original = ENV["ANLAGE_DEFINITION_BUNDLE"]
    example.run
  ensure
    original ? ENV["ANLAGE_DEFINITION_BUNDLE"] = original : ENV.delete("ANLAGE_DEFINITION_BUNDLE")
  end

  def document = Nokogiri::HTML(response.body)
  def show(subject_id) = get("/patients/#{OpenehrRails::Rm::Ehr.find_by!(subject_id:).ehr_id}")
  def sections = document.css("section[data-definition-section]").map { _1["data-definition-section"] }
  def notice = document.at_css("#definition_notice")&.text&.squish
  # いま出している画面（組・版・画面）。部品に入れるものが無い患者でも、どの定義で出したかが分かる
  def screen = document.at_css("[data-definition-screen]")&.[]("data-definition-screen")

  context "初期データ" do
    before { Evaluation::Datasets.build("demo_initial") }

    it "設定が無ければ、組み込みの定義（印は出さない）" do
      ENV.delete("ANLAGE_DEFINITION_BUNDLE")
      DefinitionBundle.register(Definitions::Files.read(fixture), registered_by: "rake").bundle.activate!

      show("DEMO-01")

      expect(sections).to eq(%w[problem_list time_series lab_table records])
      expect(notice).to be_nil
    end

    it "設定した組の active の版の start の画面の、部品の並びで出る（部品は from に書いたものだけ）" do
      ENV["ANLAGE_DEFINITION_BUNDLE"] = "clinic_spec"
      DefinitionBundle.register(Definitions::Files.read(fixture), registered_by: "rake").bundle.activate!

      show("DEMO-01")

      expect(response).to have_http_status(:ok)
      expect(screen).to eq("clinic_spec 0.1.0 patient_chart")
      expect(sections).to eq(%w[problems labs blood_pressure actions])
      expect(document.css("section[data-definition-section='blood_pressure'] figcaption").map(&:text))
        .to eq([ "収縮期（CardiologyEncounter、mm[Hg]）", "拡張期（CardiologyEncounter、mm[Hg]）" ])
      expect(document.at_css("section[data-definition-section='actions']").text).to include("検査結果を入力")
      expect(notice).to be_nil
    end

    it "ボタンの open.screen で、同じ組のほかの画面に移る（?screen=）。組に無い画面の名前は、start の画面" do
      ENV["ANLAGE_DEFINITION_BUNDLE"] = "clinic_spec"
      DefinitionBundle.register(Definitions::Files.read(fixture), registered_by: "rake").bundle.activate!
      show("DEMO-01")
      href = document.at_css("[data-definition-button='enter_lab']")["href"]

      get href

      expect(screen).to eq("clinic_spec 0.1.0 lab_entry")
      expect(sections).to eq(%w[lab_form lab_actions])
      expect(document.at_css("section[data-definition-section='lab_form'] a")["href"]).to eq("/forms/LabResultReport")

      get "#{href.split('?').first}?screen=no_such_screen"
      expect(screen).to eq("clinic_spec 0.1.0 patient_chart")
    end

    it "設定した組に動いている版が無ければ、組み込みの定義と、理由の文" do
      ENV["ANLAGE_DEFINITION_BUNDLE"] = "clinic_spec"
      DefinitionBundle.register(Definitions::Files.read(fixture), registered_by: "rake")

      show("DEMO-01")

      expect(sections).to eq(%w[problem_list time_series lab_table records])
      expect(notice).to eq("定義の組 clinic_spec に、動いている版がありません。既定の画面を出しています。")
    end

    it "動いている版が、いまのテンプレートで検査に通らなければ（テンプレートが外れた）、組み込みの定義と、理由の文。500 にしない" do
      ENV["ANLAGE_DEFINITION_BUNDLE"] = "clinic_spec"
      DefinitionBundle.register(Definitions::Files.read(fixture), registered_by: "rake").bundle.activate!
      Template.active.find_by!(template_id: "LabResultReport").supersede!

      show("DEMO-01")

      expect(response).to have_http_status(:ok)
      expect(sections).to eq(%w[problem_list time_series records])
      expect(notice).to start_with("定義の組 clinic_spec 0.1.0 は、いまのテンプレートで検査に通りません。既定の画面を出しています。")
      expect(document.css("#definition_notice li").map(&:text)).to include(a_string_matching(/LabResultReport.*\[D3\]|\[D3\].*LabResultReport|D3/))
    end
  end

  # R-20261128-7 の「足すこと」: 動かす・戻すが、再起動なしで、動いているサーバの次の表示に届く（別のプロセスで rake を実行した場合を含む）。
  # 別のプロセスから見えるように、この例はトランザクションの外で書き、あとで消す
  context "別のプロセスで rake を実行する" do
    self.use_transactional_tests = false

    before do
      %w[LabResultReport ProblemList CardiologyEncounter bmi_calculation].each do |name|
        Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read).save!
      end
      OpenehrRails::Rm::Ehr.create!(ehr_id: SecureRandom.uuid, subject_id: "P-REG", subject_namespace: "anlage")
    end

    after do
      DefinitionBundle.delete_all
      OpenehrRails::Rm::Ehr.where(subject_id: "P-REG").delete_all
      Template.delete_all
    end

    def rake(*args)
      system({ "RAILS_ENV" => "test" }, "bin/rails", *args, chdir: Rails.root.to_s, out: File::NULL, exception: true)
    end

    it "登録して動かすと、同じサーバの次の表示から、その組で出る。戻すと、次の表示で戻る" do
      ENV["ANLAGE_DEFINITION_BUNDLE"] = "clinic_spec"
      show("P-REG")
      expect(screen).to eq("builtin 1.0.0 patient_chart")

      rake("definitions:register", "DIR=#{fixture}")
      rake("definitions:activate", "BUNDLE=clinic_spec", "VERSION=0.1.0")
      show("P-REG")
      expect(screen).to eq("clinic_spec 0.1.0 patient_chart")

      dir = Pathname(Dir.mktmpdir).join("clinic").tap { FileUtils.cp_r(fixture, _1) }
      chart = dir.join("screens/patient_chart.yml")
      chart.write(chart.read.sub(/  - id: blood_pressure\n.*?(?=  - id: actions)/m, ""))
      dir.join("bundle.yml").write(dir.join("bundle.yml").read.sub(/^version: .*$/, "version: 0.2.0"))
      rake("definitions:register", "DIR=#{dir}")
      rake("definitions:activate", "BUNDLE=clinic_spec", "VERSION=0.2.0")
      show("P-REG")
      expect(screen).to eq("clinic_spec 0.2.0 patient_chart")

      rake("definitions:restore", "BUNDLE=clinic_spec", "VERSION=0.1.0")
      show("P-REG")
      expect(screen).to eq("clinic_spec 0.2.1 patient_chart")
    ensure
      FileUtils.remove_entry(dir.dirname) if dir
    end
  end
end
