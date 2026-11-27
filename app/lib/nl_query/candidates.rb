module NlQuery
  # LLM に渡す候補のカード（docs/design/s4-nl-aql-plan.md 1 節の 1）。
  #
  # 問いの文の全体でパスカード検索にかけると、表示する項目のカードが候補に入らない問いがある（実測: aql の 12 問のうち 4 問。
  # docs/reports/s4-nl-query-log.md R2）。なので、索引が小さい（LIMIT 枚まで）あいだは、索引のカードをすべて候補にし、
  # 検索で当たったカードを前に並べる。索引が LIMIT より大きいときは、検索で当たったカードと、同じテンプレートのカードに絞る。
  class Candidates
    LIMIT = 40

    def self.call(question, corpus: QueryBuilder::Corpus.active, limit: LIMIT)
      new(question, corpus, limit).call
    end

    def initialize(question, corpus, limit)
      @question = question.to_s
      @corpus = corpus
      @limit = limit
    end

    def call
      hits = Opt::PathcardSearch.call(@question).filter_map { |hit| @corpus.find(QueryBuilder::Corpus.ref(hit)) }
      return (hits + (@corpus.cards - hits)) if @corpus.cards.size <= @limit

      templates = hits.map { |card| card.dig("identity", "template_id") }.uniq
      siblings = @corpus.cards.select { |card| templates.include?(card.dig("identity", "template_id")) }
      (hits + (siblings - hits)).first(@limit)
    end
  end
end
