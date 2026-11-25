module Evaluation
  # 評価 v2 の 1 問（docs/design/s1-eval-v2-plan.md 2.1）。
  #   kind:   :card（問い → 期待するカードの集合）／:aql（問い → 参照 AQL の結果）
  #   status: :active（採点の母数）／:draft（人間レビュー前）／:pending（正解がコーパスに無い保留問）
  #   match:  :archetype（archetype_id の一致。v1 互換）／:card（archetype_id と at_code の両方）
  #   expected の要素は rank（順位。1 が最上位、同順位可）を持てる。rank の無い問いは全要素が同じ順位（同 7 節）
  #   selection: aql の問いの、クエリビルダーへの入力（S2 の経路。同 8 節）。無ければ nil
  #   expected が空で forbidden を持つ card の問いは「負例だけの問い」（同 9 節）。card の集計の母数に入れず、別に数える
  #   acceptable: 許容。正解でも誤りでもなく、上位に出てよい候補（forbidden とは別）
  class Question
    KINDS = %i[card aql].freeze
    STATUSES = %i[active draft pending].freeze
    MATCHES = %i[archetype card].freeze

    attr_reader :id, :kind, :status, :query, :expected, :match, :forbidden, :acceptable, :intent_tag, :notes,
                :dataset, :reference_aql, :expected_rows, :ordered, :cards, :pending_until, :source, :selection

    def initialize(id:, kind:, query:, status: :active, expected: [], match: :card, forbidden: [], acceptable: [],
                   intent_tag: nil,
                   notes: nil, dataset: nil, reference_aql: nil, expected_rows: nil, ordered: false, cards: [],
                   pending_until: nil, source: nil, selection: nil)
      @id = id
      @kind = kind
      @status = status
      @query = query
      @expected = expected
      @match = match
      @forbidden = forbidden
      @acceptable = acceptable
      @intent_tag = intent_tag
      @notes = notes
      @dataset = dataset
      @reference_aql = reference_aql
      @expected_rows = expected_rows
      @ordered = ordered
      @cards = cards
      @pending_until = pending_until
      @source = source
      @selection = selection
    end

    def active? = status == :active
    def draft? = status == :draft
    def pending? = status == :pending
    def card? = kind == :card
    def aql? = kind == :aql
    def negative_only? = card? && expected.empty? && forbidden.any?
  end
end
