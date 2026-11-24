module QueryBuilder
  # AQL のリンタ（docs/design/s2-query-builder-plan.md 2.1）。実行はしない。
  # 構文と永続的な未対応は openehr-rails の QueryValidator に任せ（判断 D2）、パスの実在・終端ホップ・型・値集合は
  # カード（Template.active の pathcards）だけを知識源に見る（判断 D1）。
  class Linter
    Model = OpenEHR::AQL::Model

    # FROM の 1 変数の結び付け。archetype_id は ArchetypePredicate のあるときだけ（c、e は nil）
    Binding = Struct.new(:variable, :class_name, :archetype_id, keyword_init: true)

    # 現行エンジンの終端ホップ（openehr 2.4.3 path_evaluator.rb ALLOWED_TERMINAL_HOPS）。それ以外は実行時に
    # "unsupported path attribute" になる（docs/upstream-candidates.md 10・11・25 項）
    ENGINE_HOPS = %w[magnitude name value].freeze
    UPSTREAM_NOTES = { "defining_code" => "10 項", "time" => "11 項", "archetype_details" => "25 項" }.freeze
    NUMERIC_TYPES = %w[DV_QUANTITY DV_COUNT].freeze
    TEMPORAL_TYPES = %w[DV_DATE_TIME DV_DATE DV_TIME].freeze
    VALUE_TYPES = %w[DV_TEXT DV_CODED_TEXT DV_DATE_TIME DV_DATE DV_TIME DV_BOOLEAN DV_DURATION DV_URI DV_EHR_URI].freeze

    class Lint
      attr_reader :findings

      def initialize(findings)
        @findings = findings
      end

      def ok? = findings.none?(&:error?)
    end

    def self.lint(aql, corpus: Corpus.active)
      new(aql, corpus).lint
    end

    def initialize(aql, corpus)
      @aql = aql
      @corpus = corpus
      @findings = []
      @resolved = {} # IdentifiedPath → [cards, hops, text]（節とホップが通ったもの。型と値集合の検査が使う）
    end

    def lint
      query = parse
      return Lint.new(@findings) unless query

      @bindings = collect_bindings(query.from_clause.containment)
      identified_paths(query).each { |path| check_identified_path(path) }
      conditions(query.where_clause&.expression).each do |condition|
        check_comparison(condition) if condition.is_a?(Model::Comparison)
        check_value_set(condition)
      end
      Lint.new(@findings)
    end

    private

    def parse
      OpenehrRails::Aql::QueryValidator.validate!(@aql)
    rescue OpenehrRails::Aql::InvalidQuery => e
      report(:error, :syntax, e.message)
      nil
    rescue OpenehrRails::Aql::UnsupportedFeature => e
      report(:error, :unsupported, e.message)
      nil
    end

    # --- FROM

    def collect_bindings(node, bindings = {})
      case node
      when Model::Containment
        collect_bindings(node.parent, bindings)
        collect_bindings(node.child, bindings)
      when Model::ContainmentAnd, Model::ContainmentOr
        collect_bindings(node.left, bindings)
        collect_bindings(node.right, bindings)
      when Model::ClassExpression
        if node.variable
          predicate = node.predicate
          archetype_id = predicate.archetype_id if predicate.is_a?(Model::ArchetypePredicate)
          bindings[node.variable] = Binding.new(variable: node.variable, class_name: node.class_name, archetype_id: archetype_id)
        end
      end
      bindings
    end

    # --- SELECT と WHERE に現れる識別パス（出現順）

    def identified_paths(query)
      paths = query.select_clause.columns.flat_map { |column| paths_in(column.expression) }
      paths += paths_in(query.where_clause.expression) if query.where_clause
      paths
    end

    def paths_in(node)
      case node
      when Model::IdentifiedPath then [ node ]
      when Model::AggregateFunctionCall then paths_in(node.path)
      when Model::FunctionCall then node.arguments.flat_map { |argument| paths_in(argument) }
      when Model::AndExpr, Model::OrExpr then paths_in(node.left) + paths_in(node.right)
      when Model::NotExpr then paths_in(node.operand)
      when Model::Comparison then paths_in(node.left) + paths_in(node.right)
      when Model::ExistsExpr then paths_in(node.path)
      when Model::LikeExpr, Model::MatchesExpr then paths_in(node.path) + paths_in(node.operand)
      else []
      end
    end

    def check_identified_path(path)
      binding = @bindings[path.variable]
      return report(:error, :variable, "変数 #{path.variable} は FROM で宣言されていない", path: path.variable) unless binding

      text = path_text(path)
      warn_name_predicates(path, text)
      unless binding.archetype_id
        return report(:info, :path, "変数 #{path.variable}（#{binding.class_name}）にアーキタイプの述語が無いので、パスは検査しない", path: text)
      end
      unless @corpus.include?(binding.archetype_id)
        return report(:error, :path, "アーキタイプ #{binding.archetype_id} は索引（active のテンプレートのカード）に無い", path: text)
      end

      node_path = node_path_of(path)
      return if node_path.nil? || node_path.empty? # ルート自身（o/name/value など）は節の検査をしない

      cards = @corpus.cards_at(binding.archetype_id, node_path)
      if cards.empty?
        candidates = @corpus.node_paths(binding.archetype_id).keys
        return report(:error, :path, "アーキタイプ #{binding.archetype_id} に節 #{node_path} は無い。候補: #{candidates.join('、')}", path: text)
      end

      hops = hops_of(path)
      @resolved[path] = [ cards, hops, text ] if check_hops(hops, cards, text)
    end

    # 節のあとの属性ホップ。[] と ["value"]（RM オブジェクトの射影）、["name", "value"]（要素名）は型を問わず許す。
    # ["value", x] は x がエンジンに届くこと、カードの rm_type に x があることを見る
    def check_hops(hops, cards, text)
      return true if hops.empty? || hops == %w[value] || hops == %w[name value]
      return report(:error, :hop, "#{text} のホップ #{hops.join('/')} は value から始まっていない", path: text) unless hops.first == "value"

      rm_types = cards.map { |card| card.dig("semantics", "rm_type") }.compact.uniq
      hop = hops[1]
      unless ENGINE_HOPS.include?(hop)
        note = UPSTREAM_NOTES[hop] || "10・11・25 項の類"
        return report(:error, :hop, "現行の AQL エンジンは value/#{hop} に届かない（終端ホップは #{ENGINE_HOPS.join('/')} のみ。" \
                                    "docs/upstream-candidates.md #{note}）", path: text)
      end
      if hops.size > 2
        return report(:error, :hop, "現行の AQL エンジンは value/#{hops[1..].join('/')} のように 2 段より深く届かない", path: text)
      end

      allowed = rm_types.any? { |type| (hop == "magnitude" && NUMERIC_TYPES.include?(type)) || (hop == "value" && VALUE_TYPES.include?(type)) }
      return true if allowed

      usable = rm_types.map { |type| NUMERIC_TYPES.include?(type) ? "value/magnitude" : "value/value" }.uniq
      report(:error, :hop, "#{rm_types.join('／')} のカードに value/#{hop} は無い。使えるのは #{usable.join('、')}", path: text)
    end

    # --- WHERE の比較: リテラルの型が終端の型に合うか

    def conditions(node)
      case node
      when Model::Comparison, Model::MatchesExpr then [ node ]
      when Model::AndExpr, Model::OrExpr then conditions(node.left) + conditions(node.right)
      when Model::NotExpr then conditions(node.operand)
      else []
      end
    end

    def check_comparison(comparison)
      path, literal = [ comparison.left, comparison.right ].partition { |operand| operand.is_a?(Model::IdentifiedPath) }.map(&:first)
      return unless path && literal.is_a?(Model::Literal) && @resolved.key?(path)

      cards, hops, text = @resolved[path]
      return unless hops.size == 2 && hops.first == "value"

      rm_types = cards.map { |card| card.dig("semantics", "rm_type") }.compact.uniq
      value = literal.value
      if hops.last == "magnitude" && !value.is_a?(Numeric)
        report(:error, :type, "#{text}（magnitude）は数値と比べる。#{value.inspect} は数値ではない", path: text)
      elsif hops.last == "value" && !value.is_a?(String)
        report(:error, :type, "#{text}（#{rm_types.join('／')} の value）は文字列と比べる。#{value.inspect} は文字列ではない", path: text)
      elsif hops.last == "value" && rm_types.all? { |type| TEMPORAL_TYPES.include?(type) } && !iso8601?(value)
        report(:error, :type, "#{text}（#{rm_types.join('／')}）は ISO 8601 の文字列と比べる（例 \"2026-01-01T00:00:00\"）。#{value.inspect} は読めない", path: text)
      end
    end

    # --- 値集合: DV_CODED_TEXT の value/value に対する = と MATCHES のリテラルが code_list の label にあるか。
    # code_list が空（外部値集合。コンテンツ防火壁により手元に展開しない）なら info。
    # コード値（defining_code）での条件は openehr 2.5.0 のあと（判断 D4）
    def check_value_set(condition)
      path, literals = value_set_operands(condition)
      return unless path && @resolved.key?(path)

      cards, hops, text = @resolved[path]
      return unless hops == %w[value value]

      coded = cards.select { |card| card.dig("semantics", "rm_type") == "DV_CODED_TEXT" }
      return if coded.empty?

      labels = coded.flat_map { |card| Array(card.dig("constraints", "value", "code_list")).map { |entry| entry["label"] } }.compact.uniq
      if labels.empty?
        return report(:info, :value_set, "#{text} は外部値集合（code_list が空）なので、値が値集合にあるかは検査できない", path: text)
      end

      unknown = literals.reject { |value| labels.include?(value) }
      return if unknown.empty?

      report(:error, :value_set, "#{text} の値集合に #{unknown.map(&:inspect).join('、')} は無い。許される値: #{labels.join('／')}", path: text)
    end

    def value_set_operands(condition)
      case condition
      when Model::MatchesExpr
        items = condition.operand.is_a?(Model::MatchesValueList) ? condition.operand.items : []
        [ condition.path, items.select { |item| item.is_a?(Model::Literal) }.map(&:value) ]
      when Model::Comparison
        return [ nil, [] ] unless condition.operator == "="

        path, literal = [ condition.left, condition.right ].partition { |operand| operand.is_a?(Model::IdentifiedPath) }.map(&:first)
        [ path, literal.is_a?(Model::Literal) ? [ literal.value ] : [] ]
      else
        [ nil, [] ]
      end
    end

    def iso8601?(value)
      Time.iso8601(value)
      true
    rescue ArgumentError
      begin
        Date.iso8601(value)
        true
      rescue ArgumentError
        false
      end
    end

    def hops_of(path)
      segments = Array(path.path&.segments)
      last = segments.rindex { |segment| segment.predicate }
      (last ? segments[(last + 1)..] : segments).map(&:attribute)
    end

    # name 述語（[archetype_id, '名前']／[at0001, '名前']）は現行エンジンが値を捨てて兄弟に fan-out する（上流候補 24 項、openehr-ruby#60）
    def warn_name_predicates(path, text)
      names = Array(path.path&.segments).filter_map do |segment|
        predicate = segment.predicate
        predicate.value if predicate.is_a?(Model::ArchetypePredicate) || predicate.is_a?(Model::NodePredicate)
      end
      return if names.empty?

      report(:warning, :name_predicate, "name 述語 #{names.map(&:inspect).join('、')} は現行の AQL エンジンが捨て、同じアーキタイプの兄弟に広がる" \
                                        "（docs/upstream-candidates.md 24 項、openehr-ruby#60 の解消まで）", path: text)
    end

    # 述語を持つ最後の PathPart までが節、残りは属性のホップ。述語が archetype／node 以外（標準述語）なら nil（検査しない）
    def node_path_of(path)
      return "" unless path.path

      segments = path.path.segments
      last = segments.rindex { |segment| segment.predicate }
      return "" unless last

      segments[0..last].map do |segment|
        next segment.attribute unless segment.predicate

        text = predicate_text(segment.predicate)
        return nil unless text

        "#{segment.attribute}[#{text}]"
      end.join("/")
    end

    def predicate_text(predicate)
      case predicate
      when Model::ArchetypePredicate then predicate.archetype_id
      when Model::NodePredicate then predicate.code
      end
    end

    # 人が読める AQL 片（ObjectPath#to_s は述語をオブジェクトのまま埋めるので自前で組む）
    def path_text(path)
      segments = Array(path.path&.segments).map do |segment|
        segment.predicate ? "#{segment.attribute}[#{predicate_text(segment.predicate) || '…'}]" : segment.attribute
      end
      [ path.variable, *segments ].join("/")
    end

    def report(severity, code, message, path: nil)
      @findings << Finding.new(severity: severity, code: code, message: message, path: path)
    end
  end
end
