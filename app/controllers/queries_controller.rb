# クエリビルダーの画面（docs/design/s2-query-builder-plan.md 6.4）。状態はすべて URL のパラメータに持ち、サーバーには保存しない。
# 実行するのは QueryBuilder::Builder が組んだ AQL だけで、AQL の文字列は受け取らない（自由な AQL は engine の「AQL 照会」）。
class QueriesController < ApplicationController
  # include_missing: 未記入を含む（値集合）。low・high: 範囲の外（数値）。or: 前の条件と「または」でつなぐ（設計書 7.4）
  Condition = Struct.new(:card, :ref, :kind, :operator, :value, :values, :from, :to, :include_missing, :low, :high, :or,
                         keyword_init: true) do
    def outside? = kind == :number && operator == "OUTSIDE"
  end

  def new
    @corpus = QueryBuilder::Corpus.active
    @query = params[:q].to_s
    @candidates = @query.present? ? Opt::PathcardSearch.call(@query) : []
    @dropped = 0
    @columns = column_refs.filter_map { |ref| find_card(ref) }
    @conditions = condition_params.filter_map { |entry| build_condition(entry) }
    # 出所の列。以前の URL（composition_name=1）も同じ列として受ける（skoba/anlage#183）
    @template_id = params[:template_id].present? || params[:composition_name].present?
    # 版をまたいで引く（docs/design/s2-cross-version-plan.md 5 節）
    @across_versions = params[:across_versions].present?
    return if @columns.empty?

    @run = QueryBuilder::Runner.call(columns: @columns, conditions: grouped_selections,
                                     template_id: @template_id, execute: params[:run].present?,
                                     across_versions: @across_versions, corpus: @corpus)
  end

  private

  def column_refs
    refs = Array(params[:columns]).map(&:to_s)
    refs << params[:add_column].to_s if params[:add_column].present?
    refs.uniq - [ params[:remove_column].to_s ]
  end

  # conditions[<番号>][card|operator|value|values[]|from|to|include_missing|low|high|or]。番号順に並べ、足す・外すを反映する
  def condition_params
    raw = params[:conditions]
    entries = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.sort_by { |index, _| index.to_i }.map(&:last) : []
    entries.delete_at(params[:remove_condition].to_i) if params[:remove_condition].present?
    entries << { "card" => params[:add_condition].to_s } if params[:add_condition].present?
    entries.select { |entry| entry.is_a?(Hash) }
  end

  def find_card(ref)
    card = @corpus.find(ref)
    @dropped += 1 unless card
    card
  end

  def build_condition(entry)
    card = find_card(entry["card"].to_s)
    return unless card

    kind = QueryBuilder::Builder.kind(card)
    operators = QueryBuilder::Builder::OPERATORS.fetch(kind)
    Condition.new(card: card, ref: QueryBuilder::Corpus.ref(card), kind: kind,
                  operator: operators.include?(entry["operator"]) ? entry["operator"] : operators.first,
                  value: entry["value"].to_s, values: Array(entry["values"]).map(&:to_s),
                  from: entry["from"].to_s, to: entry["to"].to_s,
                  include_missing: kind == :code && entry["include_missing"].present?,
                  low: entry["low"].to_s, high: entry["high"].to_s, or: entry["or"].present?)
  end

  # 「前の条件と『または』でつなぐ」が続く条件を 1 つの組（どちらかを満たす）にまとめる。先頭の条件の指定は読まない
  def grouped_selections
    groups = @conditions.each_with_index.slice_when { |_, (condition, index)| !(condition.or && index.positive?) }
    groups.map do |group|
      selections = group.map { |condition, _| selection_of(condition) }
      selections.size > 1 ? { any: selections } : selections.first
    end
  end

  def selection_of(condition)
    value = case condition.kind
    when :code then condition.values
    when :date then { from: condition.from, to: condition.to }
    else condition.outside? ? { low: condition.low, high: condition.high } : condition.value
    end
    { card: condition.card, operator: condition.operator, value: value, include_missing: condition.include_missing }
  end
end
