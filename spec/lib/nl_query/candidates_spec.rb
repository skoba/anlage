require "rails_helper"
require "support/nl_query_cards"

# LLM に渡す候補のカード（docs/design/s4-nl-aql-plan.md 1 節の 1）。問いの文の全体でパスカード検索にかけると、
# 表示する項目のカードが候補に入らない問いがある（実測。docs/reports/s4-nl-query-log.md R2）。索引が小さいあいだは、
# 索引のカードをすべて候補にし、検索で当たったカードを前に並べる。
RSpec.describe NlQuery::Candidates do
  include_context "nl_query のカード"

  def refs(cards)
    cards.map { |card| QueryBuilder::Corpus.ref(card) }
  end

  it "索引が小さいとき、索引のカードをすべて候補にする。検索で当たったカードが前" do
    hits = Opt::PathcardSearch.call("診断確度が「疑い」の傷病名")
    candidates = described_class.call("診断確度が「疑い」の傷病名", corpus: corpus)

    expect(candidates.size).to eq(corpus.cards.size)
    expect(refs(candidates).first(hits.size)).to eq(refs(hits))
    expect(refs(candidates)).to match_array(refs(corpus.cards))
  end

  it "検索で 1 枚も当たらない問いでも、候補は空にならない（「空腹時血糖の値」）" do
    expect(Opt::PathcardSearch.call("空腹時血糖の値")).to be_empty
    expect(described_class.call("空腹時血糖の値", corpus: corpus).size).to eq(corpus.cards.size)
  end

  it "候補のカードは、索引のカードそのまま（検索の点や別名の印を持ち込まない）" do
    candidates = described_class.call("診断確度が「疑い」の傷病名", corpus: corpus)

    expect(candidates).to all(satisfy { |card| !card.key?("score") && !card.key?("alias") })
  end

  it "同じ問いと索引から、いつも同じ並び" do
    first = described_class.call("収縮期血圧が 140 mmHg 以上の記録", corpus: corpus)
    again = described_class.call("収縮期血圧が 140 mmHg 以上の記録", corpus: QueryBuilder::Corpus.active)

    expect(refs(again)).to eq(refs(first))
  end

  context "索引が上限より大きいとき" do
    it "検索で当たったカードと、同じテンプレートのカードに絞り、上限で切る" do
      candidates = described_class.call("診断確度が「疑い」の傷病名", corpus: corpus, limit: 8)

      expect(candidates.size).to eq(6)
      expect(candidates.map { |card| card.dig("identity", "template_id") }.uniq).to eq([ "ProblemList" ])

      expect(described_class.call("診断確度が「疑い」の傷病名", corpus: corpus, limit: 4).size).to eq(4)
    end

    it "検索で 1 枚も当たらなければ、候補は空" do
      expect(described_class.call("空腹時血糖の値", corpus: corpus, limit: 8)).to be_empty
    end
  end
end
