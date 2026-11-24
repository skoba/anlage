require "rails_helper"

# クエリビルダーの本体（docs/design/s2-query-builder-plan.md 6.3）。入力はカードと条件だけで、AQL の文字列を返す。
# カード・アーキタイプ ID・at-code は実物（spec/fixtures/opt/*.opt から抽出）。期待する AQL は評価 v2 の参照 AQL
# （spec/fixtures/evaluation/v2/aql.yml の a001〜a005）と同じ形（AS の別名だけ無い）。
RSpec.describe QueryBuilder::Builder do
  BP = "openEHR-EHR-OBSERVATION.blood_pressure.v2".freeze
  PD = "openEHR-EHR-EVALUATION.problem_diagnosis.v1".freeze
  LAB = "openEHR-EHR-OBSERVATION.laboratory_test_result.v1".freeze
  ANALYTE = "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1".freeze

  before do
    %w[CardiologyEncounter ProblemList LabResultReport jp_referral].each do |fixture_name|
      template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture_name}.opt").read)
      template.pathcards = Opt::PathcardExtractor.call(template).cards
      template.save!
    end
  end

  let(:corpus) { QueryBuilder::Corpus.active }

  def card(template_id, archetype_id, at_code)
    corpus.cards.find do |candidate|
      candidate["identity"].values_at("template_id", "archetype_id", "at_code") == [ template_id, archetype_id, at_code ]
    end || raise("カードが無い: #{template_id} #{archetype_id} #{at_code}")
  end

  def build(**selection)
    described_class.build(**selection)
  end

  let(:systolic) { card("CardiologyEncounter", BP, "at0004") }
  let(:diagnosis) { card("ProblemList", PD, "at0002") }
  let(:certainty) { card("ProblemList", PD, "at0073") }
  let(:onset) { card("ProblemList", PD, "at0077") }
  let(:analyte_name) { card("LabResultReport", ANALYTE, "at0024") }
  let(:analyte_result) { card("LabResultReport", ANALYTE, "at0001") }

  describe ".kind（カードの型 → 条件の種類）" do
    it "DV_QUANTITY は number、code_list のある DV_CODED_TEXT は code、DV_DATE_TIME は date、外部値集合の DV_CODED_TEXT と DV_TEXT は text" do
      expect([ systolic, certainty, onset, diagnosis, analyte_name ].map { |c| described_class.kind(c) })
        .to eq(%i[number code date text text])
    end
  end

  describe ".build" do
    it "数値比較: 収縮期（at0004）> 110 から、a001 と同じ形の AQL を組む" do
      aql = build(columns: [ systolic ], conditions: [ { card: systolic, operator: ">", value: "110" } ])

      expect(aql).to eq(<<~AQL.chomp)
        SELECT o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude
        FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[#{BP}]
        WHERE o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude > 110
      AQL
    end

    it "値集合: 診断確度（at0073）のコード at0074 から、a002 と同じ形（value/defining_code/code_string の MATCHES）を組む" do
      aql = build(columns: [ diagnosis ], conditions: [ { card: certainty, operator: "MATCHES", value: [ "at0074" ] } ])

      expect(aql).to eq(<<~AQL.chomp)
        SELECT ev/data[at0001]/items[at0002]/value/value
        FROM EHR e CONTAINS COMPOSITION c CONTAINS EVALUATION ev[#{PD}]
        WHERE ev/data[at0001]/items[at0073]/value/defining_code/code_string MATCHES {"at0074"}
      AQL
    end

    it "文書名つき・文字列のいずれか: a003 と同じ形（c/name/value を先頭に、value/value の MATCHES）を組む" do
      aql = build(columns: [ diagnosis ], composition_name: true,
                  conditions: [ { card: diagnosis, operator: "MATCHES", value: [ "2型糖尿病", "高血圧症" ] } ])

      expect(aql).to eq(<<~AQL.chomp)
        SELECT c/name/value, ev/data[at0001]/items[at0002]/value/value
        FROM EHR e CONTAINS COMPOSITION c CONTAINS EVALUATION ev[#{PD}]
        WHERE ev/data[at0001]/items[at0002]/value/value MATCHES {"2型糖尿病", "高血圧症"}
      AQL
    end

    it "埋め込み CLUSTER: 分析名（at0024）= 空腹時血糖 で分析結果（at0001）を引く。a004 と同じ形（ENTRY の変数から items[CLUSTER] を辿る）" do
      aql = build(columns: [ analyte_result ], conditions: [ { card: analyte_name, operator: "=", value: "空腹時血糖" } ])

      expect(aql).to eq(<<~AQL.chomp)
        SELECT o/data[at0001]/events[at0002]/data[at0003]/items[#{ANALYTE}]/items[at0001]/value/magnitude
        FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[#{LAB}]
        WHERE o/data[at0001]/events[at0002]/data[at0003]/items[#{ANALYTE}]/items[at0024]/value/value = "空腹時血糖"
      AQL
    end

    it "日付の範囲: 発症日時（at0077）の from 以上・to 未満。片方だけでもよい。条件どうしは AND" do
      both = build(columns: [ diagnosis ], conditions: [ { card: onset, operator: "BETWEEN", value: { from: "2020-01-01", to: "2021-01-01" } } ])
      from_only = build(columns: [ diagnosis ], conditions: [ { card: onset, operator: "BETWEEN", value: { from: "2020-01-01", to: "" } },
                                                              { card: certainty, operator: "MATCHES", value: [ "at0076" ] } ])

      expect(both.lines.last).to eq(
        'WHERE ev/data[at0001]/items[at0077]/value/value >= "2020-01-01" AND ev/data[at0001]/items[at0077]/value/value < "2021-01-01"'
      )
      expect(from_only.lines.last).to eq(
        'WHERE ev/data[at0001]/items[at0077]/value/value >= "2020-01-01" AND ' \
        'ev/data[at0001]/items[at0073]/value/defining_code/code_string MATCHES {"at0076"}'
      )
    end

    it "条件が無ければ WHERE を書かない" do
      expect(build(columns: [ systolic ]).lines.size).to eq(2)
    end

    it "SECTION 配下のカード（jp_referral の problem_diagnosis）からも、ProblemList のカードと同じ AQL を組む（テンプレートを横断する 1 本の変数）" do
      nested = { columns: [ card("jp_referral", PD, "at0002") ],
                 conditions: [ { card: card("jp_referral", PD, "at0073"), operator: "MATCHES", value: [ "at0074" ] } ] }
      flat = { columns: [ diagnosis ], conditions: [ { card: certainty, operator: "MATCHES", value: [ "at0074" ] } ] }

      expect(build(**nested)).to eq(build(**flat))
      expect(build(**nested)).not_to include("SECTION")
    end

    it "包含は LIKE の glob（*値*）にし、文字列の引用符とバックスラッシュはエスケープする" do
      contains = build(columns: [ analyte_name ], conditions: [ { card: analyte_name, operator: "CONTAINS", value: "血糖" } ])
      quoted = build(columns: [ analyte_name ], conditions: [ { card: analyte_name, operator: "=", value: 'a"b\\c' } ])

      expect(contains.lines.last).to end_with('items[at0024]/value/value LIKE "*血糖*"')
      expect(quoted.lines.last).to end_with('items[at0024]/value/value = "a\\"b\\\\c"')
      expect(OpenEHR::AQL.parse(quoted).where_clause.expression.right.value).to eq('a"b\\c')
    end

    it "組めない選択は InvalidSelection で止める（項目なし、ENTRY が 2 つ、型に合わない演算子、数値でない値、glob の文字、空の値）" do
      invalid = QueryBuilder::Builder::InvalidSelection

      expect { build(columns: []) }.to raise_error(invalid, /表示する項目/)
      expect { build(columns: [ systolic, diagnosis ]) }.to raise_error(invalid, /1 つ/)
      expect { build(columns: [ systolic ], conditions: [ { card: diagnosis, operator: "=", value: "x" } ]) }.to raise_error(invalid, /1 つ/)
      expect { build(columns: [ systolic ], conditions: [ { card: systolic, operator: "CONTAINS", value: "1" } ]) }.to raise_error(invalid, /CONTAINS/)
      expect { build(columns: [ systolic ], conditions: [ { card: systolic, operator: ">", value: "高い" } ]) }.to raise_error(invalid, /数値/)
      expect { build(columns: [ analyte_name ], conditions: [ { card: analyte_name, operator: "CONTAINS", value: "血*糖" } ]) }.to raise_error(invalid, /\*/)
      expect { build(columns: [ diagnosis ], conditions: [ { card: certainty, operator: "MATCHES", value: [] } ]) }.to raise_error(invalid, /値/)
      expect { build(columns: [ diagnosis ], conditions: [ { card: onset, operator: "BETWEEN", value: { from: "", to: "" } } ]) }.to raise_error(invalid, /値/)
    end

    it "組んだ AQL はどれもリンタを通る（error なし）" do
      selections = [
        { columns: [ systolic ], conditions: [ { card: systolic, operator: ">=", value: 110.5 } ] },
        { columns: [ diagnosis ], conditions: [ { card: certainty, operator: "MATCHES", value: %w[at0074 at0075] } ] },
        { columns: [ diagnosis ], composition_name: true, conditions: [ { card: diagnosis, operator: "CONTAINS", value: "糖尿病" } ] },
        { columns: [ analyte_result, analyte_name ], conditions: [ { card: analyte_name, operator: "=", value: "空腹時血糖" } ] },
        { columns: [ diagnosis, onset ], conditions: [ { card: onset, operator: "BETWEEN", value: { from: "2020-01-01", to: "2021-01-01" } } ] }
      ]

      selections.each do |selection|
        lint = QueryBuilder::Linter.lint(build(**selection))
        expect(lint.findings.select(&:error?)).to be_empty, "#{build(**selection)}\n#{lint.findings.map(&:message).join("\n")}"
      end
    end
  end
end
