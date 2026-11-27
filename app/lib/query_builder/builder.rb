module QueryBuilder
  # クエリビルダーの本体（docs/design/s2-query-builder-plan.md 6.3）。カード（Template.active の pathcards のハッシュ）と
  # 条件から AQL の文字列を組む。自然言語は入らない。意味（パス・型・値集合）はカードから取り、ここで決めるのは AQL の形だけ。
  #   columns:          射影するカードの配列
  #   conditions:       [{ card:, operator:, value: }]。AND でつなぐ。7 節（R-20261125-6）の 3 つの形:
  #                       未記入を含む     { card:, operator: "MATCHES", value: [コード], include_missing: true }（値集合だけ）
  #                       範囲の外         { card:, operator: "OUTSIDE", value: { low:, high: } }（数値だけ）
  #                       どちらかを満たす { any: [条件, 条件, …] }（2 つ以上。入れ子にしない）
  #   template_id:      真なら先頭に c/archetype_details/template_id/value（出所のテンプレート。skoba/anlage#183）
  #   order:            並べ替え { card:, direction: :asc／:desc }（skoba/anlage#242）。数値は magnitude、文字列は value の順。
  #                     日時の項目は、まだ組まない（openehr 2.6.1 は、日時そのものの順が月末で逆になることがある。既知の制限 20）
  class Builder
    class InvalidSelection < StandardError; end

    # ENTRY の RM 型 → FROM の変数名
    ENTRY_VARIABLES = { "OBSERVATION" => "o", "EVALUATION" => "ev", "INSTRUCTION" => "i", "ACTION" => "a", "ADMIN_ENTRY" => "ad" }.freeze
    ENTRY_PREDICATE = /\AopenEHR-EHR-(#{ENTRY_VARIABLES.keys.join('|')})\./
    NUMERIC_TYPES = %w[DV_QUANTITY DV_COUNT].freeze
    DATE_TYPES = %w[DV_DATE_TIME DV_DATE].freeze
    # 条件の種類 → 使える演算子
    OPERATORS = {
      number: %w[> >= < <= = OUTSIDE], code: %w[MATCHES], date: %w[BETWEEN], text: %w[= MATCHES CONTAINS]
    }.freeze

    # 出所の列（記録のテンプレート）。openehr 2.6.1・openehr-rails 0.11.0 から AQL で届く
    TEMPLATE_ID_PATH = "c/archetype_details/template_id/value".freeze

    Entry = Struct.new(:rm_type, :archetype_id, :path, keyword_init: true) do
      def variable = ENTRY_VARIABLES.fetch(rm_type)
    end

    DIRECTIONS = { "asc" => "ASC", "desc" => "DESC" }.freeze

    def self.build(columns:, conditions: [], template_id: false, order: nil)
      new(columns, conditions, template_id, order).build
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

    def initialize(columns, conditions, template_id, order = nil)
      @columns = Array(columns)
      @conditions = Array(conditions)
      @template_id = template_id
      @order = order
    end

    def build
      raise InvalidSelection, "表示する項目が 1 つも無い" if @columns.empty?

      raise InvalidSelection, "並べ替える項目が無い" if @order && @order[:card].nil?

      entries = (@columns + @conditions.flat_map { |condition| cards_of(condition) } + [ @order&.fetch(:card) ].compact).map { |card| entry_of(card) }
      archetype_ids = entries.map(&:archetype_id).uniq
      unless archetype_ids.size == 1
        raise InvalidSelection, "1 つのクエリで使える ENTRY のアーキタイプは 1 つ（#{archetype_ids.join('、')}）"
      end

      entry = entries.first
      select = @columns.map { |card| projection(card) }
      select.unshift(TEMPLATE_ID_PATH) if @template_id
      lines = [ "SELECT #{select.join(', ')}",
                "FROM EHR e CONTAINS COMPOSITION c CONTAINS #{entry.rm_type} #{entry.variable}[#{entry.archetype_id}]" ]
      where = @conditions.flat_map { |condition| group?(condition) ? [ any(condition) ] : clauses(condition) }
      lines << "WHERE #{where.join(' AND ')}" if where.any?
      lines << order_by if @order
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

    # 並べ替え: 数値は magnitude、文字列（値集合の表示名を含む）は value の順
    def order_by
      card = @order.fetch(:card)
      direction = DIRECTIONS[@order[:direction].to_s.downcase]
      raise InvalidSelection, "並べ替えの向きは asc か desc（#{@order[:direction].inspect}）" unless direction
      if self.class.kind(card) == :date
        raise InvalidSelection, "#{label(card)}: 日時の項目での並べ替えは、まだ使えない（openehr の版上げを待つ。既知の制限 20）"
      end

      "ORDER BY #{projection(card)} #{direction}"
    end

    def group?(condition) = condition.key?(:any)

    def cards_of(condition)
      group?(condition) ? Array(condition[:any]).reject { |member| group?(member) }.map { |member| member.fetch(:card) } : [ condition.fetch(:card) ]
    end

    # どちらかを満たす: 中の条件を OR でつなぎ、括弧でくくる。節が 2 つの条件（日付の範囲）は、その条件を先に括弧でくくる
    def any(group)
      members = Array(group[:any])
      raise InvalidSelection, "どちらかを満たすには、条件が 2 つ以上要る" if members.size < 2
      raise InvalidSelection, "どちらかを満たすは入れ子にできない" if members.any? { |member| group?(member) }

      alternatives = members.map do |member|
        parts = clauses(member)
        parts.size > 1 ? "(#{parts.join(' AND ')})" : parts.first
      end
      "(#{alternatives.join(' OR ')})"
    end

    def clauses(condition)
      card = condition.fetch(:card)
      operator = condition.fetch(:operator).to_s
      kind = self.class.kind(card)
      unless OPERATORS.fetch(kind).include?(operator)
        raise InvalidSelection, "#{label(card)}（#{card.dig('semantics', 'rm_type')}）に #{operator} は使えない。使えるのは #{OPERATORS.fetch(kind).join('／')}"
      end

      if condition[:include_missing] && kind != :code
        raise InvalidSelection, "#{label(card)}: 未記入を含むは、値集合の条件にだけ付けられる"
      end

      path = value_path(card)
      value = condition[:value]
      case kind
      when :number then operator == "OUTSIDE" ? [ outside(card, path, value) ] : [ "#{path}/magnitude #{operator} #{number(card, value)}" ]
      when :code then [ code(card, path, value, condition[:include_missing]) ]
      when :date then range(card, path, value)
      else text(card, path, operator, value)
      end
    end

    # 未記入を含む: その要素が書かれていない記録（NOT EXISTS）も当てる。null flavor は見ない（R-20261125-6）
    def code(card, path, value, include_missing)
      matches = "#{path}/defining_code/code_string MATCHES {#{strings(card, value)}}"
      include_missing ? "(#{matches} OR NOT EXISTS #{path})" : matches
    end

    # 範囲の外: 下限より低い、または上限より高い
    def outside(card, path, value)
      low, high = (value.is_a?(Hash) ? value : {}).transform_keys(&:to_sym).values_at(:low, :high)
      raise InvalidSelection, "#{label(card)} の範囲の外には、下限と上限の両方が要る" if low.to_s.strip.empty? || high.to_s.strip.empty?

      low = number(card, low)
      high = number(card, high)
      raise InvalidSelection, "#{label(card)} の下限（#{low}）が上限（#{high}）より大きい" if low.to_f > high.to_f

      "(#{path}/magnitude < #{low} OR #{path}/magnitude > #{high})"
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
