module NlQuery
  # 何をどう引いたかの説明（docs/design/s4-nl-aql-plan.md 1 節の 7）。選択（SelectionParser の selection と同じ形）と、
  # カードの文言（ラベル、容器の名前、値集合の表示名、単位）から、決まった形で組む。LLM には書かせない。
  # 入力に実行の結果が無いので、記録の中身は現れない。
  class Explanation
    COMPARISONS = { ">=" => "以上", ">" => "より大きい", "<" => "未満", "<=" => "以下", "=" => "に等しい" }.freeze

    def self.build(selection)
      new(selection).build
    end

    def initialize(selection)
      @columns = Array(selection[:columns])
      @conditions = Array(selection[:conditions])
      @template_id = selection[:template_id]
      @across_versions = selection[:across_versions]
      @order = selection[:order]
    end

    def build
      sentences = [ "#{container}#{@columns.map { |card| quote(label(card)) }.join}を表示します。" ]
      sentences << "記録のテンプレートも表示します。" if @template_id
      sentences << "条件: #{@conditions.map { |condition| phrase(condition) }.join('、かつ、')}。" if @conditions.any?
      sentences << "#{quote(label(@order[:card]))}の#{@order[:direction].to_s == 'desc' ? '降順' : '昇順'}に並べます。" if @order
      sentences << "アーキタイプの版をまたいで引きます。" if @across_versions
      sentences << "アーキタイプ: #{identities('archetype_id').join('、')}。テンプレート: #{identities('template_id').join('、')}。"
      sentences.join
    end

    private

    def cards
      @columns + @conditions.flat_map { |condition| condition.key?(:any) ? condition[:any].map { |member| member[:card] } : [ condition[:card] ] }
    end

    def identities(key)
      cards.map { |card| card.dig("identity", key) }.uniq
    end

    # 先頭の項目の、いちばん外側の容器（ENTRY）の名前
    def container
      name = @columns.first&.dig("semantics", "container_labels", 0, "text")
      name ? "#{quote(name)}の" : ""
    end

    def phrase(condition)
      return "（#{condition[:any].map { |member| phrase(member) }.join('、または、')}）" if condition.key?(:any)

      card = condition.fetch(:card)
      "#{quote(label(card))}が#{predicate(card, condition)}#{'（未記入を含む）' if condition[:include_missing]}"
    end

    def predicate(card, condition)
      operator = condition.fetch(:operator)
      value = condition[:value]
      case QueryBuilder::Builder.kind(card)
      when :number
        if operator == "OUTSIDE"
          " #{quantity(card, value[:low])} より低い、または #{quantity(card, value[:high])} より高い"
        else
          " #{quantity(card, value)} #{COMPARISONS.fetch(operator)}"
        end
      when :code then " #{any_of(Array(value).map { |code| "#{code_label(card, code)}（#{code}）" }, '、')}"
      when :date then " #{[ ("#{value[:from]} 以降" if value[:from].present?), ("#{value[:to]} より前" if value[:to].present?) ].compact.join('、')}"
      else text(operator, value)
      end
    end

    def text(operator, value)
      case operator
      when "MATCHES" then any_of(Array(value).map { |word| quote(word) }, "")
      when "CONTAINS" then "#{quote(value)}を含む"
      else "#{quote(value)}に一致"
      end
    end

    def any_of(items, separator)
      items.size > 1 ? "#{items.join(separator)}のいずれか" : items.first.to_s
    end

    def quantity(card, value)
      [ value, card.dig("constraints", "value", "units") ].compact.join(" ")
    end

    def code_label(card, code)
      QueryBuilder::Builder.code_list(card).find { |entry| entry["code"] == code }&.fetch("label", nil) || code
    end

    def label(card)
      card.dig("semantics", "labels", 0, "text") || card.dig("identity", "at_code")
    end

    def quote(text) = "「#{text}」"
  end
end
