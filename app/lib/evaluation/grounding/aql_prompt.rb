module Evaluation
  module Grounding
    # AQL を書かせる 3 つの腕に送る文（docs/design/s4-nl-aql-plan.md 5.1 節・12.2 節。R-20261127-32）。
    #   n0     接地なし。問いだけ
    #   n1     接地なし。問いと、索引にあるアーキタイプの ID の一覧
    #   g_aql  接地あり。問いと、索引のカードの文（ラベル、型、値集合、FROM の形、パス）
    # 方言の説明（instructions）は、3 つの腕で同じ文。違うのは input だけ。説明、bindings、provenance は、どの腕にも入れない。
    class AqlPrompt
      ARMS = %i[n0 n1 g_aql].freeze

      DIALECT = <<~TEXT.freeze
        あなたは、openEHR の臨床の記録を引く AQL を書きます。利用者の問い（日本語）に答える AQL を、JSON で返してください。

        返す JSON の形:
        {"aqls": ["SELECT ... FROM ... WHERE ...", ...]}

        この AQL エンジンの決まり:
        - 形は SELECT <パス>, ... FROM EHR e CONTAINS COMPOSITION c CONTAINS <RM の型> <変数>[<アーキタイプの ID>] WHERE <条件>
          例: FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2]
        - 1 本の AQL で使える ENTRY のアーキタイプは 1 つ。同じ項目が、複数のアーキタイプ（版の違いを含む）にあるときは、
          アーキタイプごとに AQL を 1 本ずつ書いて、aqls に並べる。行は、並べた順につながれる
        - 値のパスの終わり方: 数値（DV_QUANTITY）は <項目のパス>/value/magnitude、文字列と日時は <項目のパス>/value/value、
          値集合（DV_CODED_TEXT）のコードは <項目のパス>/value/defining_code/code_string、表示名は <項目のパス>/value/value
        - 条件: 数値は > >= < <= =、文字列は = と MATCHES {"a", "b"} と LIKE "*含む文字*"、コードは MATCHES {"at0001"}、
          日時は >= "2025-01-01" と < "2026-01-01" の文字の比較。AND、OR、括弧、NOT EXISTS <パス> が使える
        - 並べ替えは ORDER BY <パス> ASC か DESC。日時の項目では ORDER BY を使わない
        - 記録の出所（テンプレート）は c/archetype_details/template_id/value

        出力の決まり:
        - 記録の出所（template_id）を出すときは、最初の列に置く。ほかの列は、問いの文に出てくる順
        - 問いが求めている項目だけを SELECT に書く。AS の別名、集計、DISTINCT は使わない
        - 値は、問いの文から抜き出す。問いに無い値を作らない
        - JSON だけを返す。説明の文を付けない
      TEXT

      def initialize(arm:, question:, corpus:)
        raise ArgumentError, "腕は #{ARMS.join('／')}（#{arm.inspect}）" unless ARMS.include?(arm)

        @arm = arm
        @question = question.to_s.strip
        @corpus = corpus
      end

      def instructions = DIALECT

      def input
        parts = []
        parts << "索引にあるアーキタイプの ID:\n#{archetype_ids.join("\n")}" if @arm == :n1
        parts << "索引の項目（項目名 | 区分 | 型 | 値集合（表示名=コード） | 単位 | テンプレート | FROM に書く形 | SELECT に書くパス）:\n#{card_lines.join("\n")}" if @arm == :g_aql
        parts << "問い: #{clean(@question)}"
        "#{parts.join("\n\n")}\n"
      end

      def sha256 = Llm.fingerprint(instructions: instructions, input: input)

      private

      def archetype_ids
        @corpus.cards.filter_map { |card| entry(card)&.last }.uniq.sort
      end

      def card_lines
        @corpus.cards.filter_map do |card|
          projection, from = entry(card)&.first(2)
          next unless projection

          codes = QueryBuilder::Builder.code_list(card).select { |code| code["code"].to_s.match?(NlQuery::Prompt::LOCAL_CODE) }
          [ card.dig("semantics", "labels", 0, "text"),
            Array(card.dig("semantics", "container_labels")).map { |container| container["text"] }.join("／"),
            NlQuery::Prompt::KIND_NAMES.fetch(QueryBuilder::Builder.kind(card)),
            codes.map { |code| "#{code['label']}=#{code['code']}" }.join("、"),
            card.dig("constraints", "value", "units"),
            card.dig("identity", "template_id"), from, projection ].map { |field| clean(field) }.join(" | ")
        end
      end

      # カード → [SELECT に書くパス, FROM に書く形, ENTRY のアーキタイプの ID]。クエリビルダーが組んだ AQL から取る（形を二重に持たない）
      def entry(card)
        select, from = QueryBuilder::Builder.build(columns: [ card ]).lines.map(&:strip)
        clause = from[/CONTAINS COMPOSITION c CONTAINS (.+)\z/, 1]
        [ select.delete_prefix("SELECT "), clause, clause[/\[(.+)\]/, 1] ]
      rescue QueryBuilder::Builder::InvalidSelection
        nil
      end

      def clean(field) = field.to_s.gsub(/[|\r\n]+/, " ").squeeze(" ").strip
    end
  end
end
