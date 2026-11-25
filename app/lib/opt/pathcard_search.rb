module Opt
  class PathcardSearch
    def self.call(query)
      new(query).call
    end

    def initialize(query)
      @query_bigrams = bigrams(query.to_s)
    end

    def call
      return [] if @query_bigrams.empty?

      # 索引は active 版のみ（skoba/anlage#32）。superseded 版のカードは系譜・diff 用に
      # 保持するが、同一カードが版ごとに並ぶのを避けるため索引から外す。
      # 同点の順序は、template_id、テンプレートの中でのカードの並び（帳票の順）で決める。
      # テンプレートの登録順に左右させない（skoba/anlage#122）。
      Template.active.where.not(pathcards: nil).flat_map do |template|
        Array(template.pathcards).each_with_index.filter_map do |card, position|
          score = (@query_bigrams & card_bigrams(card)).size
          [ card.merge("score" => score), position ] if score.positive?
        end
      end.sort_by { |card, position| [ -card.fetch("score"), card.dig("identity", "template_id").to_s, position ] }.map(&:first)
    end

    private

    def card_bigrams(card)
      searchable_texts(card).flat_map { |text| bigrams(text) }.uniq
    end

    def searchable_texts(card)
      semantics = card.fetch("semantics", {})
      labels = Array(semantics["labels"]).filter_map { |entry| entry["text"] }
      descriptions = Array(semantics["descriptions"]).filter_map { |entry| entry["text"] }
      code_labels = Array(card.dig("constraints", "value", "code_list")).filter_map do |entry|
        entry["label"]
      end

      # スキーマ v1.2: 祖先ルート名（様式11 の欄名 = AD がルートに与えた名前）も
      # 索引する（skoba/anlage#31）。v1.1 カードはキーが無いので空。
      container_labels = Array(semantics["container_labels"]).filter_map { |entry| entry["text"] }

      labels + descriptions + code_labels + container_labels
    end

    def bigrams(text)
      text.to_s.each_char.each_cons(2).map(&:join).uniq
    end
  end
end
