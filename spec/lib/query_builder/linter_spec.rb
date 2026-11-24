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

  context "CardiologyEncounter・ProblemList・jp_referral が索引済みの場合" do
    before do
      %w[CardiologyEncounter ProblemList jp_referral].each do |fixture_name|
        template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture_name}.opt").read)
        template.pathcards = Opt::PathcardExtractor.call(template).cards
        template.save!
      end
    end

    describe "パスの実在" do
      it "存在する節パス（血圧 at0004）は findings 無しで ok?" do
        lint = lint(<<~AQL)
          SELECT o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude AS systolic
          FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2]
          WHERE o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude > 110
        AQL

        expect(lint.findings).to be_empty
        expect(lint.ok?).to be(true)
      end

      it "存在しない節（items[at0099]）は error（パス）で、同じアーキタイプの候補パスを添える" do
        lint = lint(<<~AQL)
          SELECT o/data[at0001]/events[at0006]/data[at0003]/items[at0099]/value/magnitude
          FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2]
        AQL

        finding = lint.findings.first
        expect(lint.findings.size).to eq(1)
        expect(finding).to have_attributes(severity: :error, code: :path, path: "o/data[at0001]/events[at0006]/data[at0003]/items[at0099]/value/magnitude")
        expect(finding.message).to include("openEHR-EHR-OBSERVATION.blood_pressure.v2", "data[at0001]/events[at0006]/data[at0003]/items[at0004]",
                                           "data[at0001]/events[at0006]/data[at0003]/items[at0005]")
      end

      it "SECTION 配下の ENTRY（jp_referral の problem_diagnosis）も、アーキタイプのルートから相対に切って見つける" do
        lint = lint(<<~AQL)
          SELECT ev/data[at0001]/items[at0002]/value/value AS diagnosis
          FROM EHR e CONTAINS COMPOSITION c CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
        AQL

        expect(lint.findings).to be_empty
      end

      it "アーキタイプの述語が無い変数（c、e）のパスは検査せず info にする" do
        lint = lint("SELECT c/name/value FROM EHR e CONTAINS COMPOSITION c")

        expect(lint.ok?).to be(true)
        expect(lint.findings.map { |finding| [ finding.severity, finding.code, finding.path ] }).to eq([ [ :info, :path, "c/name/value" ] ])
      end

      it "索引に無いアーキタイプを FROM に書くと error（パス）" do
        lint = lint("SELECT o/data[at0001]/items[at0004]/value/magnitude FROM EHR e CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.pulse.v2]")

        expect(lint.findings.map { |finding| [ finding.severity, finding.code ] }).to eq([ [ :error, :path ] ])
        expect(lint.findings.first.message).to include("openEHR-EHR-OBSERVATION.pulse.v2", "索引")
      end
    end
  end
end
