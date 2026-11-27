require "json"

module NlQuery
  # LLM の応答（JSON の文字列）を、クエリビルダーの選択に直して検査する（docs/design/s4-nl-aql-plan.md 2.1・2.3）。
  #
  # LLM から受け取るのは、カードの番号（Prompt が振った 1 からの連番）、演算子、値だけ。パス・型・値集合のコードは、
  # 番号から引いたカードが持つ。値集合の条件は、表示名からコードをカードで引く。応答にそれ以外のキーがあっても読まない。
  # 例外は外に出さない。結果は ok（選択がある）／unanswerable（LLM が答えられないと返した）／rejected（検査ではねた）。
  #
  # selection の形は QueryBuilder::Runner.call の引数と同じ:
  #   { columns: [カード], conditions: [条件], template_id: 真偽, across_versions: 真偽, order: { card:, direction: }（あれば） }
  class SelectionParser
    Result = Struct.new(:status, :selection, :reason, keyword_init: true) do
      def ok? = status == :ok
      def unanswerable? = status == :unanswerable
      def rejected? = status == :rejected
    end

    class Rejected < StandardError; end

    DATE = /\A\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2})?(Z|[+-]\d{2}:\d{2})?)?\z/
    NUMBER = /\A-?\d+(\.\d+)?\z/

    def self.parse(response, cards:)
      new(response, cards).parse
    end

    def initialize(response, cards)
      @response = response.to_s
      @cards = Array(cards)
    end

    def parse
      data = json
      raise Rejected, "決まった形でない応答（JSON のオブジェクトでない）" unless data.is_a?(Hash)

      columns = data["columns"]
      conditions = data.fetch("conditions", [])
      raise Rejected, "決まった形でない応答（columns が配列でない）" unless columns.is_a?(Array)
      raise Rejected, "決まった形でない応答（conditions が配列でない）" unless conditions.is_a?(Array)

      reason = data["reason"].to_s.strip
      if columns.empty? && conditions.empty?
        return Result.new(status: :unanswerable, reason: reason) unless reason.empty?

        raise Rejected, "表示する項目が 1 つも無く、理由も無い"
      end
      raise Rejected, "表示する項目が 1 つも無い" if columns.empty?

      selection = { columns: columns.map { |number| card(number) },
                    conditions: conditions.map { |condition| condition(condition, nested: false) },
                    template_id: data["template_id"] == true, across_versions: data["across_versions"] == true }
      selection[:order] = order(data["order"]) unless data["order"].nil?
      Result.new(status: :ok, selection: selection)
    rescue Rejected => e
      Result.new(status: :rejected, reason: e.message)
    end

    private

    # 応答の中の、最初の { から最後の } までを JSON として読む（コードの囲みや前置きの文が付くことがある）
    def json
      body = @response[/\{.*\}/m]
      raise Rejected, "JSON として読めない応答" if body.nil? || @response.strip.start_with?("[")

      JSON.parse(body)
    rescue JSON::ParserError
      raise Rejected, "JSON として読めない応答"
    end

    def card(number)
      raise Rejected, "カードを番号で指していない（#{number.inspect.truncate(40)}）" unless number.is_a?(Integer)
      raise Rejected, "候補に無い番号（#{number}）" unless number.between?(1, @cards.size)

      @cards[number - 1]
    end

    # 並べ替え: { "card": 番号, "direction": "asc"／"desc" }。向きが無ければ昇順
    def order(raw)
      raise Rejected, "決まった形でない並べ替え（#{raw.inspect.truncate(40)}）" unless raw.is_a?(Hash)

      direction = raw.fetch("direction", "asc").to_s.downcase
      raise Rejected, "並べ替えの向きは asc か desc（#{direction.truncate(20)}）" unless %w[asc desc].include?(direction)

      { card: card(raw["card"]), direction: direction }
    end

    def condition(raw, nested:)
      raise Rejected, "決まった形でない条件（#{raw.inspect.truncate(40)}）" unless raw.is_a?(Hash)
      return any(raw["any"], nested) if raw.key?("any")

      card = card(raw["card"])
      operator = raw["operator"].to_s
      kind = QueryBuilder::Builder.kind(card)
      unless QueryBuilder::Builder::OPERATORS.fetch(kind).include?(operator)
        raise Rejected, "#{label(card)} に #{operator.empty? ? '演算子が無い' : "#{operator} は使えない"}"
      end
      raise Rejected, "#{label(card)}: 未記入を含むは、値集合の条件にだけ付けられる" if raw["include_missing"] == true && kind != :code

      selection = { card: card, operator: operator, value: value(card, kind, operator, raw["value"]) }
      selection[:include_missing] = true if raw["include_missing"] == true
      selection
    end

    def any(members, nested)
      raise Rejected, "どちらかを満たすは入れ子にできない" if nested
      raise Rejected, "どちらかを満たすには、条件が 2 つ以上要る" unless members.is_a?(Array) && members.size >= 2

      { any: members.map { |member| condition(member, nested: true) } }
    end

    def value(card, kind, operator, raw)
      case kind
      when :number then operator == "OUTSIDE" ? bounds(card, raw, %w[low high], required: true) { |bound| number(card, bound) } : number(card, raw)
      when :code then codes(card, raw)
      when :date then bounds(card, raw, %w[from to], required: false) { |bound| date(card, bound) }
      else operator == "MATCHES" ? strings(card, raw) : string(card, raw)
      end
    end

    def number(card, raw)
      return raw if raw.is_a?(Numeric)
      return (raw.include?(".") ? raw.to_f : raw.to_i) if raw.is_a?(String) && raw.strip.match?(NUMBER)

      raise Rejected, "#{label(card)} の値 #{raw.inspect.truncate(40)} は数値ではない"
    end

    def date(card, raw)
      return raw if raw.is_a?(String) && raw.match?(DATE)

      raise Rejected, "#{label(card)} の値 #{raw.inspect.truncate(40)} は日付（2025-01-01 の形）ではない"
    end

    # { low:, high: } や { from:, to: }。required が偽なら、片方だけでもよい
    def bounds(card, raw, keys, required:)
      raise Rejected, "#{label(card)} の値が、範囲の形でない" unless raw.is_a?(Hash)

      present = keys.select { |key| !raw[key].nil? && raw[key].to_s.strip != "" }
      raise Rejected, "#{label(card)} の範囲の値が無い" if present.empty? || (required && present.size < keys.size)

      present.to_h { |key| [ key.to_sym, yield(raw[key]) ] }
    end

    # 値集合: 表示名 → コード。カードの値集合に無い表示名は、はねる
    def codes(card, raw)
      labels = Array(raw)
      raise Rejected, "#{label(card)} の値が 1 つも無い" if labels.empty?

      labels.map do |name|
        entry = QueryBuilder::Builder.code_list(card).find { |candidate| candidate["label"] == name.to_s.strip }
        raise Rejected, "#{label(card)} の値集合に「#{name.to_s.truncate(40)}」は無い" unless entry

        entry["code"]
      end
    end

    def strings(card, raw)
      list = Array(raw).map { |text| string(card, text) }
      raise Rejected, "#{label(card)} の値が 1 つも無い" if list.empty?

      list
    end

    def string(card, raw)
      text = raw.is_a?(String) || raw.is_a?(Numeric) ? raw.to_s.strip : ""
      raise Rejected, "#{label(card)} の値が無い" if text.empty?

      text
    end

    def label(card)
      card.dig("semantics", "labels", 0, "text") || "項目"
    end
  end
end
