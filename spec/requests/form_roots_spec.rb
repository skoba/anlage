require "rails_helper"

# skoba/anlage#119（M2 の E）: 帳票の入力欄を、ルート（SECTION → ENTRY → 埋め込み CLUSTER）ごとの入れ子の fieldset にまとめ、
# ルートのテンプレート上の名前を legend にする。名前は OPT の term_definitions の実測（docs/reports/m2-exit-log.md R2）。
RSpec.describe "帳票のルートごとのまとまり（#119）", type: :request do
  def register(fixture)
    Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture}").read).tap do |template|
      template.pathcards = Opt::PathcardExtractor.call(template).cards
      template.save!
    end
  end

  def document
    Nokogiri::HTML(response.body)
  end

  # fieldset の入れ子を [legend, [子の fieldset …]] の木にする
  def tree(node)
    node.xpath("./fieldset[contains(@class, 'root-group')]").map { |fs| [ fs.at_xpath("./legend").text.strip, tree(fs) ] }
  end

  def legend_path_of(input_name)
    input = document.at_css("[name='values[#{input_name}]']")
    input.ancestors("fieldset.root-group").map { |fs| fs.at_xpath("./legend").text.strip }.reverse
  end

  describe "jp_referral" do
    let!(:template) { register("jp_referral.opt") }

    before { get "/forms/jp_referral" }

    it "入力欄の数（26）が、パスカードの枚数と一致する" do
      inputs = document.css("form [name^='values[']").map { _1["name"] }.reject { _1.include?("__") }.uniq

      expect(inputs.size).to eq(26)
      expect(inputs.size).to eq(template.pathcards.size)
    end

    it "ルートの入れ子が SECTION → ENTRY → CLUSTER の順に fieldset になり、テンプレート上の名前が legend になる" do
      expect(tree(document.at_css("form"))).to eq([
        [ "紹介状の詳細情報", [
          [ "サービス依頼", [
            [ "紹介元医療機関", [ [ "住所", [] ], [ "電子的な連絡先", [] ], [ "医師", [] ] ] ],
            [ "紹介先医療機関", [ [ "診療科", [ [ "担当医", [] ] ] ] ] ]
          ] ],
          [ "傷病名", [] ],
          [ "既往歴及び家族歴", [] ],
          [ "症状経過及び検査結果", [] ],
          [ "治療経過", [] ]
        ] ]
      ])
    end

    it "同じアーキタイプの 2 つのルートの項目は、それぞれのルートの fieldset に入る" do
      expect(legend_path_of("organisation_at0001")).to eq(%w[紹介状の詳細情報 サービス依頼 紹介元医療機関])
      expect(legend_path_of("organisation_at0001_2")).to eq(%w[紹介状の詳細情報 サービス依頼 紹介先医療機関])
      expect(legend_path_of("person_at0001_2")).to eq(%w[紹介状の詳細情報 サービス依頼 紹介先医療機関 診療科 担当医])
    end
  end

  it "SECTION も埋め込みルートも無いテンプレート（ProblemList）は、ENTRY の fieldset 1 つ" do
    register("ProblemList.opt")

    get "/forms/ProblemList"

    expect(tree(document.at_css("form"))).to eq([ [ "プロブレム・診断", [] ] ])
  end
end

# R-20261125-1: 帳票の必須の印は「この枠に書くなら必須」と分かる出し方にする（docs/demo/ui-vocabulary.md）。
# 任意の入れ物の中の必須の要素は「※」、常に書かれる入れ物の中の必須の要素は「*」。帳票の先頭に凡例を出す
RSpec.describe "帳票の必須の印（R-20261125-1）", type: :request do
  it "ProblemList の傷病名（0..1 の ENTRY の中の 1..1）は「この枠に書くなら必須」の印を持ち、凡例が出る" do
    template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!)

    get "/forms/#{template.template_id}"

    label = Nokogiri::HTML(response.body).at_css("label[for='field_problem_diagnosis_at0002']")
    expect(label.text).to include("※")
    expect(label.text).not_to include("*")
    expect(response.body).to include("※ この枠に書くなら必須")
  end
end
