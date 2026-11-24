module Opt
  # 2 つの版のパスカードの差分（skoba/anlage#100、docs/design/m3-plan.md W5）。
  # キーは identity.path（その項目の意味上の同一性。Opt::TemplateDiff が field の path を使うのと同じ考え方）。
  # パスカードのスキーマ（v1.2）は読むだけで、変えない。
  #   added / removed  片方にしか無いカード（カードそのもの）
  #   changed          両方にあり中身が違うカード: { "path", "at_code", "label", "changes" => [ { "aspect", "before", "after" } ] }
  class PathcardDiff
    Result = Struct.new(:added, :removed, :changed, keyword_init: true) do
      def any_changes?
        added.any? || removed.any? || changed.any?
      end
    end

    # 観点ごとに、カードから比べる値を取り出す。文言（text）だけを比べ、未翻訳の判定などの付随情報は比べない
    ASPECTS = {
      "labels" => ->(card) { texts(card.dig("semantics", "labels")) },
      "descriptions" => ->(card) { texts(card.dig("semantics", "descriptions")) },
      "container_labels" => ->(card) { texts(card.dig("semantics", "container_labels")) },
      "rm_type" => ->(card) { card.dig("semantics", "rm_type") },
      "constraints" => ->(card) { card["constraints"] },
      "bindings" => ->(card) { card["bindings"] }
    }.freeze

    def self.call(old_cards, new_cards)
      new(old_cards, new_cards).call
    end

    def self.texts(entries)
      Array(entries).map { |entry| entry["text"] }
    end

    def initialize(old_cards, new_cards)
      @old = index(old_cards)
      @new = index(new_cards)
    end

    def call
      Result.new(
        added: @new.except(*@old.keys).values,
        removed: @old.except(*@new.keys).values,
        changed: (@old.keys & @new.keys).filter_map { |path| changed_card(path) }
      )
    end

    private

    def index(cards)
      Array(cards).map { |card| card.deep_stringify_keys }.index_by { |card| card.dig("identity", "path") }
    end

    def changed_card(path)
      before = @old[path]
      after = @new[path]
      changes = ASPECTS.filter_map do |aspect, extract|
        old_value = extract.call(before)
        new_value = extract.call(after)
        { "aspect" => aspect, "before" => old_value, "after" => new_value } unless old_value == new_value
      end
      return if changes.empty?

      { "path" => path, "at_code" => after.dig("identity", "at_code"), "label" => self.class.texts(after.dig("semantics", "labels")).first, "changes" => changes }
    end
  end
end
