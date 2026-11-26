require "rails_helper"

RSpec.describe "Pathcard search", type: :request do
  it "renders the matching card for a Japanese query" do
    source_xml = Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read
    template = Template.build_from_opt_xml(source_xml)
    golden = JSON.parse(
      Rails.root.join("spec/fixtures/pathcards/CardiologyEncounter.golden.json").read
    )
    template.pathcards = golden.fetch("cards")
    template.save!

    get "/pathcards/search", params: { q: "収縮期" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("収縮期")
    expect(response.body).to include("CardiologyEncounter")
    expect(response.body).to include("at0004")
  end

  it "warns when matching card semantics contain suspected untranslated text" do
    source_xml = Rails.root.join("spec/fixtures/opt/LabResultReport.opt").read
    template = Template.build_from_opt_xml(source_xml)
    golden = JSON.parse(
      Rails.root.join("spec/fixtures/pathcards/LabResultReport.golden.json").read
    )
    template.pathcards = golden.fetch("cards")
    template.save!

    get "/pathcards/search", params: { q: "analyte" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("未翻訳の疑いがあります")
  end

  # skoba/anlage#64（裁定 R-20261116-1）: 導出は Opt::Pathcard.archetype_path、view は出すだけ。
  describe "アーキタイプパス" do
    def register_with_cards(fixture)
      template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture}.opt").read)
      cards = JSON.parse(Rails.root.join("spec/fixtures/pathcards/#{fixture}.golden.json").read).fetch("cards")
      template.pathcards = block_given? ? yield(cards) : cards
      template.save!
    end

    def archetype_paths
      Nokogiri::HTML(response.body).css(".pathcard").map do |card|
        terms = card.css("dt").map { _1.text.strip }
        [ card.at_css("h2").text.strip, terms.include?("アーキタイプパス"), card.at_css("dd code.archetype-path")&.text ]
      end
    end

    it "検索結果の各カードに、所属アーキタイプを根としたパスが出る（jp_referral 傷病名）" do
      register_with_cards("jp_referral")

      get "/pathcards/search", params: { q: "傷病名" }

      expect(archetype_paths).to include(
        [ "プロブレム・診断の名称", true, "/data[at0001]/items[at0002]/value" ]
      )
      expect(archetype_paths.map { _1[1] }).to all(be(true))
    end

    it "埋め込み CLUSTER 配下のカードは CLUSTER を根とした相対パスが出る（LabResultReport 分析結果）" do
      register_with_cards("LabResultReport")

      get "/pathcards/search", params: { q: "分析結果" }

      expect(archetype_paths).to include([ "分析結果", true, "/items[at0001]/value" ])
    end

    it "述語が path に無いカードは「アーキタイプパス」の行を出さない（path を差し替えた合成カード）" do
      register_with_cards("ProblemList") do |cards|
        cards.map do |card|
          next card unless card.dig("identity", "at_code") == "at0002"

          card.merge("identity" => card.fetch("identity").merge("path" => "/data[at0001]/items[at0002]/value"))
        end
      end

      get "/pathcards/search", params: { q: "プロブレム・診断名" }

      expect(archetype_paths).to include([ "プロブレム・診断名", false, nil ])
    end
  end
  # 別名表（skoba/anlage#152）で出たカードの理由と、「対応させない」行だけに当たったときの案内（R-20261125-11）。
  # 表はリポジトリの config/search_aliases.yml。文言は docs/demo/ui-vocabulary.md の写し
  describe "別名で出た理由と、特定できない語の案内" do
    before do
      %w[ProblemList LabResultReport bmi_calculation].each do |fixture_name|
        template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture_name}.opt").read)
        template.pathcards = Opt::PathcardExtractor.call(template).cards
        template.save!
      end
    end

    def doc = Nokogiri::HTML(response.body)
    def reasons = doc.css("#pathcard-results .pathcard").map { |card| card.at_css(".alias-reason")&.text&.strip }

    it "別名で出たカードには「別名「<語>」で一致」と出る（既往 → プロブレム・診断の 6 枚）" do
      get "/pathcards/search", params: { q: "既往" }

      expect(reasons).to eq([ "別名「既往」で一致" ] * 6)
    end

    it "字面で当たったカードには出ない。別名のカードと字面のカードが混じるときは、別名のカードにだけ出る（臨床検査）" do
      get "/pathcards/search", params: { q: "診断" }
      expect(reasons.compact).to be_empty

      get "/pathcards/search", params: { q: "臨床検査" }
      expect(reasons).to eq([ "別名「臨床検査」で一致", nil, nil, nil ])
    end

    it "「対応させない」行だけに当たって 0 件のときは、その語だけでは項目を特定できないと案内する（判定）" do
      get "/pathcards/search", params: { q: "判定" }

      expect(doc.css("#pathcard-results .pathcard")).to be_empty
      expect(doc.at_css("#search-guidance").text.strip).to eq("「判定」だけでは、項目を特定できません。ほかの語と組み合わせて探してください。")
    end

    it "ただ当たらなかっただけの語と、検索の前には、案内を出さない" do
      get "/pathcards/search", params: { q: "脈拍" }
      expect(doc.at_css("#search-guidance")).to be_nil

      get "/pathcards/search"
      expect(doc.at_css("#search-guidance")).to be_nil
    end
  end
end
