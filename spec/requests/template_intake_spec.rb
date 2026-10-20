require "rails_helper"

# skoba/anlage#47 変更 2: 取り込み画面（台本 1 幕）。文言は docs/demo/ui-vocabulary.md（正典）の写し。
# 版の並記: 登録版＝registry 連番（Template#version）、テンプレート版＝OPT の sem_ver。
RSpec.describe "デモ動線: テンプレートの取り込み", type: :request do
  let(:jp_referral_path) { Rails.root.join("spec/fixtures/opt/jp_referral.opt") }

  def upload_xml(xml, filename:)
    file = Tempfile.new([ "intake", ".opt" ])
    file.write(xml)
    file.flush
    Rack::Test::UploadedFile.new(file.path, "text/xml", false, original_filename: filename)
  end

  def doc = Nokogiri::HTML(response.body)

  describe "POST /templates/preview（取り込みプレビュー）" do
    it "見出しは「テンプレートの取り込み: <テンプレート名>」、説明 1 行と登録版／テンプレート版を並記する" do
      post templates_preview_path, params: { file: upload_xml(jp_referral_path.read, filename: "jp_referral.opt") }

      expect(doc.at_css("h2").text.strip).to eq("テンプレートの取り込み: jp_referral")
      expect(response.body).to include("登録前に中身を確認します")
      expect(doc.at_css("#version_label").text.strip).to eq("登録版 v1.0.0／テンプレート版 0.2.0")
    end

    it "sem_ver を持たない OPT は登録版だけを出す" do
      post templates_preview_path, params: { file: upload_xml(Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt").read, filename: "bp.opt") }

      expect(doc.at_css("#version_label").text.strip).to eq("登録版 v1.0.0")
    end

    # 実物の OPT に XML コメントを 1 行足しただけの「内容が変わった同じ template_id」（捏造しない）
    it "supersede 文も新旧を登録版／テンプレート版で並記する" do
      Template.build_from_opt_xml(jp_referral_path.read).tap(&:save!)

      post templates_preview_path, params: { file: upload_xml(jp_referral_path.read + "<!-- intake spec -->\n", filename: "jp_referral.opt") }

      text = doc.at_css("#version_diff").text.squish
      expect(text).to include("登録版 v1.0.0／テンプレート版 0.2.0 として登録済みです")
      expect(text).to include("登録版 v1.0.1／テンプレート版 0.2.0 として新規登録し")
      expect(doc.at_css("#version_label").text.strip).to eq("登録版 v1.0.1／テンプレート版 0.2.0")
    end
  end

  describe "GET /templates（カタログ）" do
    it "カードに登録版／テンプレート版を並記する" do
      Template.build_from_opt_xml(jp_referral_path.read).tap(&:save!)

      get templates_path

      expect(doc.at_css(".template-card .version-label").text.strip).to eq("登録版 v1.0.0／テンプレート版 0.2.0")
    end

    it "「ファイルを選択」がボタンの主導線で、ページ全体がドロップ対象" do
      get templates_path

      expect(doc.at_css("button#dropzone_hint").text.strip).to eq("ファイルを選択")
      actions = doc.at_css("[data-controller='dropzone']")["data-action"].split
      expect(actions).to include("dragenter@window->dropzone#dragenter", "dragleave@window->dropzone#dragleave",
                                 "dragover@window->dropzone#dragover", "drop@window->dropzone#drop")
    end
  end

  # 表示切替は JS（.visible の付け外し）、見え方は CSS。CSS 側の存在をスタイルシート本文で pin する
  describe "application.css" do
    it "オーバーレイは既定で非表示、.visible で全画面に出る" do
      get ActionController::Base.helpers.asset_path("application.css")
      css = response.body.gsub(/\s+/, " ")

      expect(css).to match(/#dropzone_overlay \{[^}]*display: none/)
      expect(css).to match(/#dropzone_overlay\.visible \{[^}]*display: flex[^}]*position: fixed[^}]*inset: 0/)
    end
  end
end
