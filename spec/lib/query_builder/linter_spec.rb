require "rails_helper"

# AQL のリンタ（docs/design/s2-query-builder-plan.md 2.1）。実行はせず、カード（Template.active の pathcards）だけを知識源にする。
# テストTODO（設計書 3 節）:
# 1. 構文 / 2. 変数 / 3. 存在する節パス / 4. 存在しない節と SECTION 配下 / 5. 終端ホップ / 6. 型 / 7. 値集合 / 8. name 述語 / 9. QueryValidator
RSpec.describe QueryBuilder::Linter do
  def lint(aql)
    described_class.lint(aql)
  end

  describe "構文" do
    it "構文の誤りは error（構文）1 件になり、ok? は false" do
      lint = lint("SELECT FROM WHERE")

      expect(lint.ok?).to be(false)
      expect(lint.findings.map { |finding| [ finding.severity, finding.code ] }).to eq([ [ :error, :syntax ] ])
      expect(lint.findings.first.message).to be_present
    end
  end

  describe "変数" do
    it "FROM で宣言していない変数を SELECT／WHERE に使うと error（変数）になり、その変数名を path に持つ" do
      lint = lint(<<~AQL)
        SELECT x/name/value FROM EHR e CONTAINS COMPOSITION c
        WHERE y/data[at0001]/items[at0002]/value/value = "a"
      AQL

      expect(lint.findings.map { |finding| [ finding.severity, finding.code, finding.path ] })
        .to eq([ [ :error, :variable, "x" ], [ :error, :variable, "y" ] ])
    end
  end
end
