require "digest"

module Evaluation
  module Grounding
    # 測定に使う問いの文（spec/fixtures/evaluation/nl/nl_queries.yml。レビュー済み）を読み、正解の行を、ファイルの冒頭の決まりで引く
    # （docs/design/s4-nl-aql-plan.md 12 節）。調整用（tuning）は読まない。
    #   1. 自前の expected_rows を持つ問い（名指し、検査）は、それ
    #   2. base が both_versions にあれば、v1 と v2 の両方を引いた行。片方の版だけの行は partial_rows（見落とし）
    #   3. それ以外は、base の問い（評価 v2 のゴールド）の expected_rows
    module Queries
      PATH = "spec/fixtures/evaluation/nl/nl_queries.yml".freeze

      Query = Struct.new(:id, :base, :style, :tags, :nl_query, :expected_rows, :partial_rows, :cards,
                         :both_versions, :overlook_measurable, :selection_only, :sorted_column, keyword_init: true) do
        def both_versions? = both_versions ? true : false
        # 見落とし（片方の版だけ）を見分けられるか。片方の版に当たる記録が無い問い（a009）は、見分けられない
        def overlook_measurable? = overlook_measurable ? true : false
        # 選択を出す腕だけで数える問い（もとから版をまたぐ a014 の文）
        def selection_only? = selection_only ? true : false
        def value_paraphrase? = Array(tags).include?("value_paraphrase")
      end

      module_function

      def sha256(path = Rails.root.join(PATH)) = Digest::SHA256.file(path).hexdigest

      def load(path = Rails.root.join(PATH))
        data = YAML.load_file(path, permitted_classes: [ Date ], aliases: true)
        gold = Evaluation::Questions.from_v2.select(&:aql?).index_by(&:id)
        data.fetch("queries").reject { |entry| entry["style"] == "tuning" }.map { |entry| build(entry, data.fetch("both_versions", {}), gold) }
      end

      def build(entry, both_versions, gold)
        base = gold[entry["base"]]
        # sorted_column: 行の順を見る問い（n013-2）の、並んでいるはずの列（0 から数える）。向きと、同じ値どうしの順は問わない
        common = { id: entry["id"], base: entry["base"], style: entry["style"], tags: Array(entry["tags"]), nl_query: entry["nl_query"],
                   sorted_column: entry["sorted_column"] }
        if entry["expected_rows"]
          Query.new(**common, expected_rows: entry["expected_rows"], cards: cards_of(entry.fetch("selection")))
        elsif (both = both_versions[entry["base"]])
          by_archetype = both.fetch("rows_by_archetype")
          Query.new(**common, expected_rows: by_archetype.values.flatten(1), partial_rows: by_archetype, cards: base.cards,
                              both_versions: true, overlook_measurable: by_archetype.values.none?(&:empty?))
        else
          Query.new(**common, expected_rows: base.expected_rows, cards: base.cards, selection_only: base.selection&.fetch(:across_versions, false))
        end
      end

      def cards_of(selection)
        refs = Array(selection["columns"]) + Array(selection["conditions"]).map { |condition| condition["card"] }
        refs.map { |ref| ref.transform_keys(&:to_sym) }.uniq
      end
    end
  end
end
