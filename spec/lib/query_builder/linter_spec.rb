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

    describe "終端ホップ" do
      it "DV_TEXT のカード（検査名 at0005 は LabResultReport、ここでは jp_referral の紹介目的 at0062）に value/magnitude は error（終端ホップ）" do
        lint = lint(<<~AQL)
          SELECT i/activities[at0001]/description[at0009]/items[at0062]/value/magnitude
          FROM EHR e CONTAINS COMPOSITION c CONTAINS INSTRUCTION i[openEHR-EHR-INSTRUCTION.service_request.v1]
        AQL

        expect(lint.findings.map { |finding| [ finding.severity, finding.code ] }).to eq([ [ :error, :hop ] ])
        expect(lint.findings.first.message).to include("DV_TEXT", "magnitude", "value/value")
      end

      it "value/defining_code/code_string は現行エンジンが届かないので error（終端ホップ）に上流候補 10 項を添える" do
        lint = lint(<<~AQL)
          SELECT ev/data[at0001]/items[at0073]/value/defining_code/code_string
          FROM EHR e CONTAINS COMPOSITION c CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
        AQL

        expect(lint.findings.map { |finding| [ finding.severity, finding.code ] }).to eq([ [ :error, :hop ] ])
        expect(lint.findings.first.message).to include("defining_code", "upstream-candidates.md", "10")
      end

      it "value だけ（RM オブジェクトの射影）と name/value（要素名）は許し、value/units は現行エンジンが届かないので error（終端ホップ）" do
        lint = lint(<<~AQL)
          SELECT o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value,
                 o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/name/value,
                 o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/units
          FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2]
        AQL

        expect(lint.findings.map { |finding| [ finding.severity, finding.code ] }).to eq([ [ :error, :hop ] ])
        expect(lint.findings.first.message).to include("units", "magnitude")
      end
    end

    describe "型" do
      it "magnitude と文字列リテラルの比較は error（型）" do
        lint = lint(<<~AQL)
          SELECT o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude
          FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2]
          WHERE o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude > "110"
        AQL

        expect(lint.findings.map { |finding| [ finding.severity, finding.code ] }).to eq([ [ :error, :type ] ])
        expect(lint.findings.first.message).to include("magnitude", "数値")
      end

      it "DV_DATE_TIME の value/value に ISO 8601 で読めない文字列は error（型）。読める文字列は通る" do
        bad = lint(<<~AQL)
          SELECT ev/data[at0001]/items[at0003]/value/value
          FROM EHR e CONTAINS COMPOSITION c CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
          WHERE ev/data[at0001]/items[at0003]/value/value >= "2026年1月1日"
        AQL
        good = lint(<<~AQL)
          SELECT ev/data[at0001]/items[at0003]/value/value
          FROM EHR e CONTAINS COMPOSITION c CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
          WHERE ev/data[at0001]/items[at0003]/value/value >= "2026-01-01T00:00:00" AND ev/data[at0001]/items[at0003]/value/value < "2026-07-01T00:00:00"
        AQL

        expect(bad.findings.map { |finding| [ finding.severity, finding.code ] }).to eq([ [ :error, :type ] ])
        expect(bad.findings.first.message).to include("ISO 8601")
        expect(good.findings).to be_empty
      end

      it "DV_TEXT の value/value と数値リテラルの比較は error（型）" do
        lint = lint(<<~AQL)
          SELECT i/activities[at0001]/description[at0009]/items[at0062]/value/value
          FROM EHR e CONTAINS COMPOSITION c CONTAINS INSTRUCTION i[openEHR-EHR-INSTRUCTION.service_request.v1]
          WHERE i/activities[at0001]/description[at0009]/items[at0062]/value/value = 3
        AQL

        expect(lint.findings.map { |finding| [ finding.severity, finding.code ] }).to eq([ [ :error, :type ] ])
      end
    end

    describe "値集合" do
      def certainty(where)
        lint(<<~AQL)
          SELECT ev/data[at0001]/items[at0002]/value/value
          FROM EHR e CONTAINS COMPOSITION c CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
          WHERE ev/data[at0001]/items[at0073]/value/value #{where}
        AQL
      end

      it "診断確度 at0073 の MATCHES {\"疑い\", \"推定\"} と = \"確定\" は値集合に含まれ、findings 無し" do
        expect(certainty('MATCHES {"疑い", "推定"}').findings).to be_empty
        expect(certainty('= "確定"').findings).to be_empty
      end

      it "値集合に無い値（疑惑）は error（値集合）に、許される値（疑い／推定／確定）を添える" do
        lint = certainty('MATCHES {"疑い", "疑惑"}')

        expect(lint.findings.map { |finding| [ finding.severity, finding.code ] }).to eq([ [ :error, :value_set ] ])
        expect(lint.findings.first.message).to include("疑惑", "疑い", "推定", "確定")
      end

      it "code_list の無い DV_CODED_TEXT（傷病名 at0002、外部値集合）は info（検査できない）" do
        lint = lint(<<~AQL)
          SELECT c/name/value
          FROM EHR e CONTAINS COMPOSITION c CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
          WHERE ev/data[at0001]/items[at0002]/value/value MATCHES {"2型糖尿病", "高血圧症"}
        AQL

        expect(lint.ok?).to be(true)
        expect(lint.findings.map { |finding| [ finding.severity, finding.code ] }).to include([ :info, :value_set ])
        expect(lint.findings.find { |finding| finding.code == :value_set }.message).to include("外部", "検査できない")
      end
    end

    describe "name 述語と永続的な未対応" do
      it "name 述語（[openEHR-EHR-CLUSTER.organisation.v1, '紹介先医療機関']）は warning（上流候補 24 項）。ok? は true のまま" do
        lint = lint(<<~AQL)
          SELECT i/protocol[at0008]/items[openEHR-EHR-CLUSTER.organisation.v1, '紹介先医療機関']/items[at0001]/value/value
          FROM EHR e CONTAINS COMPOSITION c CONTAINS INSTRUCTION i[openEHR-EHR-INSTRUCTION.service_request.v1]
        AQL

        expect(lint.ok?).to be(true)
        expect(lint.findings.map { |finding| [ finding.severity, finding.code ] }).to eq([ [ :warning, :name_predicate ] ])
        expect(lint.findings.first.message).to include("紹介先医療機関", "24")
      end

      it "QueryValidator が永続的に未対応とするもの（VERSIONED_COMPOSITION の FROM。VERSION は構文で落ちる）は error（unsupported）に写す" do
        lint = lint("SELECT c/name/value FROM EHR e CONTAINS VERSIONED_COMPOSITION vc CONTAINS COMPOSITION c")

        expect(lint.findings.map { |finding| [ finding.severity, finding.code ] }).to eq([ [ :error, :unsupported ] ])
      end
    end
  end
end
