module QueryBuilder
  # AQL のリンタ（docs/design/s2-query-builder-plan.md 2.1）。実行はしない。
  # 構文と永続的な未対応は openehr-rails の QueryValidator に任せ（判断 D2）、パスの実在・終端ホップ・型・値集合は
  # カード（Template.active の pathcards）だけを知識源に見る（判断 D1）。
  class Linter
    Model = OpenEHR::AQL::Model

    # FROM の 1 変数の結び付け。archetype_id は ArchetypePredicate のあるときだけ（c、e は nil）
    Binding = Struct.new(:variable, :class_name, :archetype_id, keyword_init: true)

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
    end

    def lint
      query = parse
      return Lint.new(@findings) unless query

      @bindings = collect_bindings(query.from_clause.containment)
      identified_paths(query).each { |path| check_identified_path(path) }
      Lint.new(@findings)
    end

    private

    def parse
      OpenehrRails::Aql::QueryValidator.validate!(@aql)
    rescue OpenehrRails::Aql::InvalidQuery => e
      report(:error, :syntax, e.message)
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
      unless binding.archetype_id
        return report(:info, :path, "変数 #{path.variable}（#{binding.class_name}）にアーキタイプの述語が無いので、パスは検査しない", path: text)
      end
      unless @corpus.include?(binding.archetype_id)
        return report(:error, :path, "アーキタイプ #{binding.archetype_id} は索引（active のテンプレートのカード）に無い", path: text)
      end

      node_path = node_path_of(path)
      return if node_path.nil? || node_path.empty? # ルート自身（o/name/value など）は節の検査をしない

      cards = @corpus.cards_at(binding.archetype_id, node_path)
      return unless cards.empty?

      candidates = @corpus.node_paths(binding.archetype_id).keys
      report(:error, :path, "アーキタイプ #{binding.archetype_id} に節 #{node_path} は無い。候補: #{candidates.join('、')}", path: text)
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
