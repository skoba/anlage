module NlQuery
  # 選択（SelectionParser の selection）を、クエリビルダーの画面の URL のパラメータに直す（QueriesController#new が読む形）。
  # LLM が作った選択は、画面の「表示する項目」「条件」に入り、利用者が見て、直してから実行する（docs/design/s4-nl-aql-plan.md 1 節）。
  #   columns[]、conditions[<番号>][card|operator|value|values[]|from|to|include_missing|low|high|or]、template_id、across_versions
  class QueryParams
    def self.from(selection)
      new(selection).to_h
    end

    def initialize(selection)
      @selection = selection
    end

    def to_h
      params = { columns: Array(@selection[:columns]).map { |card| ref(card) } }
      entries = Array(@selection[:conditions]).flat_map { |condition| entries_of(condition) }
      params[:conditions] = entries.each_with_index.to_h { |entry, index| [ index.to_s, entry ] } if entries.any?
      params[:template_id] = "1" if @selection[:template_id]
      params[:across_versions] = "1" if @selection[:across_versions]
      params
    end

    private

    def ref(card) = QueryBuilder::Corpus.ref(card)

    # 1 つの条件 → 画面の条件の並び。どちらかを満たす（any）と、文字列のいずれか（MATCHES。画面に入力が無い）は、
    # 2 つめ以降に「前の条件と『または』でつなぐ」の印を付けて並べる
    def entries_of(condition)
      members = condition.key?(:any) ? condition[:any].flat_map { |member| alternatives(member) } : alternatives(condition)
      members.each_with_index.map { |entry, index| index.zero? ? entry : entry.merge(or: "1") }
    end

    def alternatives(condition)
      card = condition.fetch(:card)
      operator = condition.fetch(:operator)
      value = condition[:value]
      base = { card: ref(card), operator: operator }
      case QueryBuilder::Builder.kind(card)
      when :number then [ operator == "OUTSIDE" ? base.merge(low: value[:low].to_s, high: value[:high].to_s) : base.merge(value: value.to_s) ]
      when :code then [ base.merge(values: Array(value)).merge(condition[:include_missing] ? { include_missing: "1" } : {}) ]
      when :date then [ base.merge(value.slice(:from, :to).transform_values(&:to_s)) ]
      else operator == "MATCHES" ? Array(value).map { |word| base.merge(operator: "=", value: word.to_s) } : [ base.merge(value: value.to_s) ]
      end
    end
  end
end
