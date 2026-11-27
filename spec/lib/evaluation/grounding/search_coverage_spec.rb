require "rails_helper"

# 検索だけで、問いに必要なカードが候補に入る割合（LLM を呼ばずに出せる。R-20261127-25 の 3。検索の強化の材料）。
# 問いの文の全体をパスカード検索にかけ、問いが指すカードが、すべて結果に入っているかを見る。問いの種類ごとに数える。
RSpec.describe Evaluation::Grounding::SearchCoverage do
  before { Evaluation::Datasets.build("demo_initial") }

  let(:queries) { Evaluation::Grounding::Queries.load }

  it "問いごとに、必要なカードが検索の結果に入ったか（入らなかったカード）を出す" do
    rows = described_class.call(queries).index_by { |row| row[:id] }

    expect(rows["n001-1"]).to include(covered: true, missing: [])
    expect(rows["n004-3"]).to include(covered: false, hits: 0)
    expect(rows["n004-3"][:missing].map(&:last)).to match_array(%w[at0024 at0001])
    expect(rows.size).to eq(37)
  end

  it "種類ごとの表（入った問いの数／問いの数）を、Markdown で出す" do
    report = described_class.render(queries)

    expect(report).to include("| 種類 | 問い | 必要なカードが、すべて検索の結果に入った |")
    expect(report).to match(/\| base \| 16 \| \d+\/16 \|/)
    expect(report).to match(/\| 計 \| 37 \| \d+\/37 \|/)
  end
end
