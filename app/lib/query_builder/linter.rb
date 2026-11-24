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

    def self.lint(aql)
      new(aql).lint
    end

    def initialize(aql)
      @aql = aql
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
      return if @bindings.key?(path.variable)

      report(:error, :variable, "変数 #{path.variable} は FROM で宣言されていない", path: path.variable)
    end

    def report(severity, code, message, path: nil)
      @findings << Finding.new(severity: severity, code: code, message: message, path: path)
    end
  end
end
