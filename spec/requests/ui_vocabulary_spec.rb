require "rails_helper"

# skoba/anlage#47 変更 3: 画面見出し・ボタン名・ラベルは docs/demo/ui-vocabulary.md（正典）の写し。
# 文言 pin は regression pin ではなく語彙表の写しなので、語彙表と同一コミットで更新する（裁定 G）。
RSpec.describe "UI 語彙（docs/demo/ui-vocabulary.md）", type: :request do
  def doc = Nokogiri::HTML(response.body)
  def texts(selector) = doc.css(selector).map { _1.text.strip }

  def register(fixture, with_pathcards: false)
    Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture}.opt").read).tap do |template|
      template.pathcards = JSON.parse(Rails.root.join("spec/fixtures/pathcards/#{fixture}.golden.json").read).fetch("cards") if with_pathcards
      template.save!
    end
  end

  describe "テンプレート" do
    it "一覧: 見出し・空状態・ドラッグ中のオーバーレイ" do
      get templates_path

      expect(texts("main h1, body > h1")).to eq([ "テンプレートの取り込み" ])
      expect(doc.at_css("#empty_notice").text.strip).to eq("テンプレートが未登録です。OPT ファイルを選択して取り込んでください")
      expect(doc.at_css("#dropzone_overlay").text.strip).to eq("ドロップして取り込む")
    end

    it "カードのリンクは「帳票に入力」" do
      register("ProblemList")
      get templates_path

      expect(doc.at_css(".template-card a").text.strip).to eq("帳票に入力")
    end

    it "取り込みプレビュー: 要約は「アーキタイプ数・項目数」、フォームは「帳票の確認」" do
      post templates_preview_path, params: { file: Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/opt/ProblemList.opt").to_s, "text/xml") }

      expect(texts("#fitting_room_content dt")).to eq(%w[アーキタイプ数 項目数])
      expect(texts("#fitting_room_content h3")).to include("帳票の確認")
    end
  end

  describe "帳票" do
    it "送信ボタンは「保存」" do
      template = register("ProblemList")
      get form_path(template.template_id)

      expect(texts("form button[type=submit]")).to eq([ "保存" ])
    end
  end

  describe "カルテ記録" do
    it "一覧: 見出し「カルテ記録一覧」と空状態" do
      get compositions_path

      expect(texts("body > h1")).to eq([ "カルテ記録一覧" ])
      expect(response.body).to include("カルテ記録はまだありません。")
    end
  end

  describe "パスカード" do
    it "見出し・入力ラベル・検索ボタン・カードの項目名・帳票へのリンク" do
      register("CardiologyEncounter", with_pathcards: true)
      get "/pathcards/search", params: { q: "収縮期" }

      expect(texts("body > h1")).to eq([ "パスカード検索" ])
      expect(doc.at_css("label[for=q]").text.strip).to eq("探したい項目")
      expect(doc.at_css("input[type=submit]")["value"]).to eq("検索")
      expect(texts(".pathcard dt").uniq).to eq(%w[テンプレート アーキタイプ ノード])
      expect(doc.css(".pathcard a").map { [ _1.text.strip, _1["href"] ] }.uniq).to eq([ [ "帳票に入力", "/forms/CardiologyEncounter" ] ])
    end
  end
end
