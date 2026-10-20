require "rails_helper"

# skoba/anlage#47 変更 1: 各画面が孤立せず、壇上で一本の流れとして歩ける。
# 文言は docs/demo/ui-vocabulary.md（正典）の写し（CLAUDE.md、裁定 G）。
RSpec.describe "デモ動線: 共通ナビと保存後の次アクション", type: :request do
  let!(:template) do
    Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt").read).tap(&:save!)
  end

  def links_in(selector)
    Nokogiri::HTML(response.body).css("#{selector} a").map { [ _1.text.strip, _1["href"] ] }
  end

  NAV_LINKS = [
    [ "テンプレート", "/templates" ],
    [ "カルテ記録一覧", "/compositions" ],
    [ "パスカード検索", "/pathcards/search" ],
    [ "AQL 照会", "/openehr/query" ]
  ].freeze

  describe "共通ナビ（layout）" do
    it "テンプレート・帳票・カルテ記録一覧・パスカード検索の各画面に同じ 4 リンクが出る" do
      [ "/", "/templates", "/forms/#{template.template_id}", "/compositions", "/pathcards/search" ].each do |path|
        get path

        expect(links_in("nav#app_nav")).to eq(NAV_LINKS), "#{path} のナビ"
      end
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

    it "次アクション 4 つ（同じ帳票にもう 1 件／カルテ記録一覧／AQL 照会／FHIR プロファイル）を出す" do
      expect(links_in("#next_actions")).to eq([
        [ "同じ帳票にもう 1 件入力", "/forms/patient_blood_pressure.v1" ],
        [ "カルテ記録一覧", "/compositions" ],
        [ "AQL 照会", "/openehr/query" ],
        [ "FHIR プロファイル", "/fhir/r5/StructureDefinition/openehr-observation-heart-rate-pulse-v1" ]
      ])
    end

    it "canonical JSON は折りたたみ（<details>）の中に置く" do
      pre = Nokogiri::HTML(response.body).at_css("details > pre")

      expect(JSON.parse(pre.text)["_type"]).to eq("COMPOSITION")
    end
  end
end
