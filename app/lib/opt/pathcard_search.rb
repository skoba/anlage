module Opt
  class PathcardSearch
    # 項目の重み（docs/design/s3-search-plan.md 3 節の段 B。値の根拠と感度は docs/reports/s3-search-log.md R5）
    FIELD_WEIGHTS = { label: 4, nearest_container: 3, outer_containers: 2, code_label: 2, description: 1 }.freeze

    def self.call(query, aliases: SearchAliases.default)
      new(query, aliases).call
    end

    def initialize(query, aliases = SearchAliases.default)
      @query_bigrams = bigrams(query.to_s)
      # 別名表（docs/design/s3-search-plan.md 3.1、skoba/anlage#152）。問いの全体が表の語と同じときだけ、行が引ける
      @alias_row = aliases.lookup(query)
    end

    def call
      return [] if @query_bigrams.empty? && @alias_row.nil?

      # 索引は active 版のみ（skoba/anlage#32）。superseded 版のカードは系譜・diff 用に
      # 保持するが、同一カードが版ごとに並ぶのを避けるため索引から外す。
      # 並びは、別名の対応先の順（別名で当たったカードが先）→ 字面の score → template_id →
      # テンプレートの中でのカードの並び（帳票の順）。テンプレートの登録順に左右させない（skoba/anlage#122）。
      Template.active.where.not(pathcards: nil).flat_map do |template|
        Array(template.pathcards).each_with_index.filter_map { |card, position| candidate(card, position) }
      end.sort_by { |_, key| key }.map(&:first)
    end

    private

    NOT_ALIASED = Float::INFINITY

    # [結果に出すカード, 並べ替えのキー]。出さないカードは nil
    def candidate(card, position)
      target = @alias_row&.target_index(card)
      return nil if target && @alias_row.exclude?

      score = score_for(card)
      return nil unless target || score.positive?

      hit = card.merge("score" => score)
      hit = hit.merge("alias" => @alias_row.term) if target
      [ hit, [ target || NOT_ALIASED, -score, card.dig("identity", "template_id").to_s, position ] ]
    end

    # 問いの bigram ごとに、それを含む項目の重みを足す（skoba/anlage#127）。
    # 同じ bigram がラベルと祖先の名前の両方にあれば、両方の重みが入る。
    def score_for(card)
      fields = field_bigrams(card)
      @query_bigrams.sum do |bigram|
        FIELD_WEIGHTS.sum { |field, weight| fields.fetch(field).include?(bigram) ? weight : 0 }
      end
    end

    def field_bigrams(card)
      semantics = card.fetch("semantics", {})
      # スキーマ v1.2: 祖先ルート名（様式11 の欄名 = AD がルートに与えた名前）も
      # 索引する（skoba/anlage#31）。v1.1 カードはキーが無いので空。並びは外側から内側
      containers = texts(semantics["container_labels"], "text")

      {
        label: texts(semantics["labels"], "text"),
        nearest_container: containers.last(1),
        outer_containers: containers[0...-1].to_a,
        code_label: texts(card.dig("constraints", "value", "code_list"), "label"),
        description: texts(semantics["descriptions"], "text")
      }.transform_values { |field_texts| field_texts.flat_map { |text| bigrams(text) }.uniq }
    end

    def texts(entries, key)
      Array(entries).filter_map { |entry| entry[key] }
    end

    def bigrams(text)
      text.to_s.each_char.each_cons(2).map(&:join).uniq
    end
  end
end
