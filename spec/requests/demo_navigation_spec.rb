require "rails_helper"

# skoba/anlage#47 変更 1: 各画面が孤立せず、壇上で一本の流れとして歩ける。
# 文言は docs/demo/ui-vocabulary.md（正典）の写し（CLAUDE.md、裁定 G）。
RSpec.describe "デモ動線: 共通ナビと保存後の次アクション", type: :request do
  before { select_patient } # skoba/anlage#161: 記録は、患者を選んでから保存する（spec/support/patient_selection.rb）

  let!(:template) do
    Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt").read).tap(&:save!)
  end

  def links_in(selector)
    Nokogiri::HTML(response.body).css("#{selector} a").map { [ _1.text.strip, _1["href"] ] }
  end

  NAV_LINKS = [
    [ "患者", "/patients" ],
    [ "テンプレート", "/templates" ],
    [ "カルテ記録一覧", "/compositions" ],
    [ "パスカード検索", "/pathcards/search" ],
    [ "クエリビルダー", "/queries/new" ],
    [ "AQL 照会", "/openehr/query" ]
  ].freeze

  describe "共通ナビ（layout）" do
    it "テンプレート・帳票・カルテ記録一覧・パスカード検索・クエリビルダーの各画面に同じ 6 リンクが出る" do
      [ "/", "/patients", "/templates", "/forms/#{template.template_id}", "/compositions", "/pathcards/search", "/queries/new" ].each do |path|
        get path

        expect(links_in("nav#app_nav")).to eq(NAV_LINKS), "#{path} のナビ"
      end
    end
  end

  # skoba/anlage#95（M3 の W1・W2）: ナビは左に置き、いまの画面の項目に印（aria-current）を付ける。
  # engine の画面（AQL 照会）にも同じナビを出す。文言は変えない。
  describe "統合レイアウト（#95）" do
    def current_items
      Nokogiri::HTML(response.body).css("nav#app_nav a[aria-current='page']").map { _1.text.strip }
    end

    it "ナビは作業面（main#workspace）の外にあり、作業面に画面の中身が入る" do
      get "/compositions"

      document = Nokogiri::HTML(response.body)
      expect(document.css("body > nav#app_nav")).not_to be_empty
      expect(document.css("body > main#workspace h1").map(&:text)).to eq([ "カルテ記録一覧" ])
    end

    it "いまの画面の項目に印が付く（帳票はテンプレート、カルテ記録は一覧の項目）" do
      {
        "/patients" => [ "患者" ], "/" => [ "テンプレート" ], "/templates" => [ "テンプレート" ], "/forms/#{template.template_id}" => [ "テンプレート" ],
        "/compositions" => [ "カルテ記録一覧" ], "/pathcards/search" => [ "パスカード検索" ], "/queries/new" => [ "クエリビルダー" ]
      }.each do |path, expected|
        get path

        expect(current_items).to eq(expected), "#{path} の印"
      end
    end

    it "AQL 照会（engine の画面）にも同じ 6 リンクが出て、AQL 照会に印が付く" do
      get "/openehr/query"

      expect(response).to have_http_status(:ok)
      expect(links_in("nav#app_nav")).to eq(NAV_LINKS)
      expect(current_items).to eq([ "AQL 照会" ])
    end
  end

  describe "保存後のカルテ記録画面" do
    before do
      values = template.fields.to_h { [ _1["name"], _1["rm_type"] == "DV_QUANTITY" ? "120" : "some text" ] }
      post template_compositions_path(template.template_id), params: { values: values }
      follow_redirect!
    end

    it "flash「保存しました」と見出し「カルテ記録: <テンプレート名>」を出す" do
      doc = Nokogiri::HTML(response.body)

      expect(doc.at_css("#flash").text.strip).to eq("保存しました")
      expect(doc.at_css("h1").text.strip).to eq("カルテ記録: COLNEC Patient Blood Pressure.v0")
      expect(links_in("nav#app_nav")).to eq(NAV_LINKS)
    end

    # skoba/anlage#102（M3 の W6）: FHIR プロファイルはテンプレートから決まるので、リンクはテンプレートの詳細に移した
    it "次アクション 4 つ（同じ帳票にもう 1 件／カルテ記録一覧／AQL 照会／テンプレートの詳細）を出す" do
      expect(links_in("#next_actions")).to eq([
        [ "同じ帳票にもう 1 件入力", "/forms/patient_blood_pressure.v1" ],
        [ "カルテ記録一覧", "/compositions" ],
        [ "AQL 照会", "/openehr/query" ],
        [ "テンプレートの詳細", "/templates/patient_blood_pressure.v1" ]
      ])
    end

    it "canonical JSON は折りたたみ（<details>）の中に置く" do
      pre = Nokogiri::HTML(response.body).at_css("details > pre")

      expect(JSON.parse(pre.text)["_type"]).to eq("COMPOSITION")
    end
  end
end
