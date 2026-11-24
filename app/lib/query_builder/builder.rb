module QueryBuilder
  # クエリビルダーの本体（docs/design/s2-query-builder-plan.md 6.3）。カード（Template.active の pathcards のハッシュ）と
  # 条件から AQL の文字列を組む。自然言語は入らない。意味（パス・型・値集合）はカードから取り、ここで決めるのは AQL の形だけ。
  #   columns:          射影するカードの配列
  #   conditions:       [{ card:, operator:, value: }]。AND でつなぐ
  #   composition_name: 真なら先頭に c/name/value（出所の文書名）
  class Builder
    class InvalidSelection < StandardError; end

    # ENTRY の RM 型 → FROM の変数名
    ENTRY_VARIABLES = { "OBSERVATION" => "o", "EVALUATION" => "ev", "INSTRUCTION" => "i", "ACTION" => "a", "ADMIN_ENTRY" => "ad" }.freeze
    ENTRY_PREDICATE = /\AopenEHR-EHR-(#{ENTRY_VARIABLES.keys.join('|')})\./
    NUMERIC_TYPES = %w[DV_QUANTITY DV_COUNT].freeze
    DATE_TYPES = %w[DV_DATE_TIME DV_DATE].freeze
    # 条件の種類 → 使える演算子
    OPERATORS = {
      number: %w[> >= < <= =], code: %w[MATCHES], date: %w[BETWEEN], text: %w[= MATCHES CONTAINS]
    }.freeze

    Entry = Struct.new(:rm_type, :archetype_id, :path, keyword_init: true) do
      def variable = ENTRY_VARIABLES.fetch(rm_type)
    end

    def self.build(columns:, conditions: [], composition_name: false)
      new(columns, conditions, composition_name).build
    end

    # カードの型 → 条件の種類（:number／:code／:date／:text）
    def self.kind(card)
      rm_type = card.dig("semantics", "rm_type")
      return :number if NUMERIC_TYPES.include?(rm_type)
      return :date if DATE_TYPES.include?(rm_type)
      return :code if rm_type == "DV_CODED_TEXT" && code_list(card).any?

      :text
    end

    def self.code_list(card)
      Array(card.dig("constraints", "value", "code_list"))
    end

    def initialize(columns, conditions, composition_name)
      @columns = Array(columns)
      @conditions = Array(conditions)
      @composition_name = composition_name
    end

    def build
      raise InvalidSelection, "表示する項目が 1 つも無い" if @columns.empty?

      entries = (@columns + @conditions.map { |condition| condition.fetch(:card) }).map { |card| entry_of(card) }
      archetype_ids = entries.map(&:archetype_id).uniq
      unless archetype_ids.size == 1
        raise InvalidSelection, "1 つのクエリで使える ENTRY のアーキタイプは 1 つ（#{archetype_ids.join('、')}）"
      end

      entry = entries.first
      select = @columns.map { |card| projection(card) }
      select.unshift("c/name/value") if @composition_name
      lines = [ "SELECT #{select.join(', ')}",
                "FROM EHR e CONTAINS COMPOSITION c CONTAINS #{entry.rm_type} #{entry.variable}[#{entry.archetype_id}]" ]
      where = @conditions.flat_map { |condition| clauses(condition) }
      lines << "WHERE #{where.join(' AND ')}" if where.any?
      lines.join("\n")
    end

    private

    # カードの path を ENTRY の述語の節で切る: [ENTRY, そこから下のパス（末尾は /value）]。
    # SECTION は FROM に書かない（CONTAINS が子孫を辿る。判断 G1）。埋め込み CLUSTER は下のパスに残る
    def entry_of(card)
      segments = card.dig("identity", "path").to_s.split("/").reject(&:empty?)
      index = segments.rindex { |segment| segment[/\[(.+)\]\z/, 1].to_s.match?(ENTRY_PREDICATE) }
      raise InvalidSelection, "カードのパスに ENTRY が無い（#{card.dig('identity', 'path')}）" unless index

      archetype_id = segments[index][/\[(.+)\]\z/, 1]
      Entry.new(rm_type: archetype_id[ENTRY_PREDICATE, 1], archetype_id: archetype_id, path: segments[(index + 1)..].join("/"))
    end

    def value_path(card)
      entry = entry_of(card)
      "#{entry.variable}/#{entry.path}"
    end

    def projection(card)
      "#{value_path(card)}/#{self.class.kind(card) == :number ? 'magnitude' : 'value'}"
    end

    def clauses(condition)
      card = condition.fetch(:card)
      operator = condition.fetch(:operator).to_s
      kind = self.class.kind(card)
      unless OPERATORS.fetch(kind).include?(operator)
        raise InvalidSelection, "#{label(card)}（#{card.dig('semantics', 'rm_type')}）に #{operator} は使えない。使えるのは #{OPERATORS.fetch(kind).join('／')}"
      end

      path = value_path(card)
      value = condition[:value]
      case kind
      when :number then [ "#{path}/magnitude #{operator} #{number(card, value)}" ]
      when :code then [ "#{path}/defining_code/code_string MATCHES {#{strings(card, value)}}" ]
      when :date then range(card, path, value)
      else text(card, path, operator, value)
      end
    end

    def text(card, path, operator, value)
      case operator
      when "MATCHES" then [ "#{path}/value MATCHES {#{strings(card, value)}}" ]
      when "CONTAINS"
        word = present!(card, value)
        raise InvalidSelection, "#{label(card)} の CONTAINS の値に * と ? は使えない（LIKE の glob の文字）" if word.match?(/[*?]/)

        [ "#{path}/value LIKE #{quote("*#{word}*")}" ]
      else [ "#{path}/value = #{quote(present!(card, value))}" ]
      end
    end

    def range(card, path, value)
      from, to = (value || {}).to_h.transform_keys(&:to_sym).values_at(:from, :to).map { |bound| bound.to_s.strip }
      raise InvalidSelection, "#{label(card)} の範囲の値が無い（from・to のどちらかが要る）" if from.empty? && to.empty?

      [ ("#{path}/value >= #{quote(from)}" unless from.empty?), ("#{path}/value < #{quote(to)}" unless to.empty?) ].compact
    end

    def number(card, value)
      return value.to_s if value.is_a?(Numeric)

      text = value.to_s.strip
      return text if text.match?(/\A-?\d+(\.\d+)?\z/)

      raise InvalidSelection, "#{label(card)} の値 #{value.inspect} は数値ではない"
    end

    def strings(card, values)
      list = Array(values).map { |value| value.to_s.strip }.reject(&:empty?)
      raise InvalidSelection, "#{label(card)} の値が 1 つも無い" if list.empty?

      list.map { |value| quote(value) }.join(", ")
    end

    def present!(card, value)
      text = value.to_s.strip
      raise InvalidSelection, "#{label(card)} の値が無い" if text.empty?

      text
    end

    # 文字列リテラル（openehr の lexer は \\ と \" のエスケープを読む。lexer.rb ESCAPES）
    def quote(text)
      %("#{text.gsub('\\') { '\\\\' }.gsub('"') { '\\"' }}")
    end

    def label(card)
      Array(card.dig("semantics", "labels")).first&.fetch("text", nil) || card.dig("identity", "at_code")
    end
  end
end
