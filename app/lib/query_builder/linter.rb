module QueryBuilder
  # AQL のリンタ（docs/design/s2-query-builder-plan.md 2.1）。実行はしない。
  # 構文と永続的な未対応は openehr-rails の QueryValidator に任せ（判断 D2）、パスの実在・終端ホップ・型・値集合は
  # カード（Template.active の pathcards）だけを知識源に見る（判断 D1）。
  class Linter
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
      parse
      Lint.new(@findings)
    end

    private

    def parse
      OpenehrRails::Aql::QueryValidator.validate!(@aql)
    rescue OpenehrRails::Aql::InvalidQuery => e
      report(:error, :syntax, e.message)
      nil
    end

    def report(severity, code, message, path: nil)
      @findings << Finding.new(severity: severity, code: code, message: message, path: path)
    end
  end
end
