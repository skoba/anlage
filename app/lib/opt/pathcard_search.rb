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

      Template.where.not(pathcards: nil).flat_map do |template|
        Array(template.pathcards).filter_map do |card|
          score = (@query_bigrams & card_bigrams(card)).size
          card.merge("score" => score) if score.positive?
        end
      end.sort_by { |card| -card.fetch("score") }
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

      labels + descriptions + code_labels
    end

    def bigrams(text)
      text.to_s.each_char.each_cons(2).map(&:join).uniq
    end
  end
end
