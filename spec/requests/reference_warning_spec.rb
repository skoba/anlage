require "rails_helper"

# 「参照実装。認証が無い」の警告（skoba/anlage#162、R-20261126-2 の 4）。全ページの見える場所と、README の先頭に出す。
# 画面は共通ナビ（app/views/layouts/_nav.html.erb）の先頭。engine の画面（AQL 照会）も同じナビを使う。
# 文言は docs/demo/ui-vocabulary.md の「警告」の行の写し。
RSpec.describe "参照実装の警告（#162）", type: :request do
  WARNING = "参照実装です。認証がありません。実在の患者のデータを入れないでください。外から届く場所で動かさないでください。".freeze

  it "どの画面にも、ナビの先頭に警告が出る（AQL 照会の engine の画面も）" do
    [ "/patients", "/templates", "/compositions", "/pathcards/search", "/queries/new", "/openehr/query" ].each do |path|
      get path

      warning = Nokogiri::HTML(response.body).at_css("nav#app_nav > p#reference_warning:first-child")
      expect(warning&.text&.squish).to eq(WARNING), "#{path} の警告"
      expect(warning["role"]).to eq("note")
    end
  end

  it "README の先頭（見出しの次）に同じ警告がある" do
    head = Rails.root.join("README.md").read.lines.first(4).join

    expect(head).to include("> **#{WARNING}**")
  end
end
