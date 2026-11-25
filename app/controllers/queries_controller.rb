# クエリビルダーの画面（docs/design/s2-query-builder-plan.md 6.4）。状態はすべて URL のパラメータに持ち、サーバーには保存しない。
# 実行するのは QueryBuilder::Builder が組んだ AQL だけで、AQL の文字列は受け取らない（自由な AQL は engine の「AQL 照会」）。
class QueriesController < ApplicationController
  Condition = Struct.new(:card, :ref, :kind, :operator, :value, :values, :from, :to, keyword_init: true)

  def new
    @corpus = QueryBuilder::Corpus.active
    @query = params[:q].to_s
    @candidates = @query.present? ? Opt::PathcardSearch.call(@query) : []
    @dropped = 0
    @columns = column_refs.filter_map { |ref| find_card(ref) }
    @conditions = condition_params.filter_map { |entry| build_condition(entry) }
    @composition_name = params[:composition_name].present?
    return if @columns.empty?

    @run = QueryBuilder::Runner.call(columns: @columns, conditions: @conditions.map { |condition| selection_of(condition) },
                                     composition_name: @composition_name, execute: params[:run].present?)
  end

  private

  def column_refs
    refs = Array(params[:columns]).map(&:to_s)
    refs << params[:add_column].to_s if params[:add_column].present?
    refs.uniq - [ params[:remove_column].to_s ]
  end

  # conditions[<番号>][card|operator|value|values[]|from|to]。番号順に並べ、足す・外すを反映する
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
                  from: entry["from"].to_s, to: entry["to"].to_s)
  end

  def selection_of(condition)
    value = case condition.kind
    when :code then condition.values
    when :date then { from: condition.from, to: condition.to }
    else condition.value
    end
    { card: condition.card, operator: condition.operator, value: value }
  end
end
