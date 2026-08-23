require "rails_helper"
require_relative "support/height_seed"
require_relative "support/problem_diagnosis_seed"

RSpec.describe "デモクエリ（案A: 実パイプライン駆動シード）", type: :model do
  describe "1. height不等号クエリ" do
    it "供給済みクエリが期待件数（1件）で実行できる" do
      HeightSeed.seed!(165.0)
      HeightSeed.seed!(170.0)
      HeightSeed.seed!(180.0)

      query = <<~AQL
        SELECT o/data[at0001]/events[at0002]/data[at0003]/items[at0004]/value/magnitude AS height
        FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.height.v2]
        WHERE o/data[at0001]/events[at0002]/data[at0003]/items[at0004]/value/magnitude > 170
      AQL

      result = OpenehrRails::Aql::Executor.execute(query)

      expect(result.rows).to eq([ [ 180.0 ] ])
    end
  end

  describe "2. MATCHES 値リスト（コード値の複数一致）" do
    it "診断確度が値リストのいずれかに一致するComposition が期待件数（2件）で抽出できる" do
      ProblemDiagnosisSeed.seed!(certainty_code: "at0074") # 疑い
      ProblemDiagnosisSeed.seed!(certainty_code: "at0075") # 推定
      ProblemDiagnosisSeed.seed!(certainty_code: "at0076") # 確定（対象外）

      # 実測により訂正: value/defining_code/code_string は現行AQLエンジンの
      # ALLOWED_TERMINAL_HOPS（openehr gem lib/openehr/aql/engine/path_evaluator.rb）
      # が magnitude/name/value のみを許可しており、defining_code 経由の
      # 深追いは "unsupported path attribute" になる（実測確認）。
      # そのためcode_stringではなくDvCodedTextの表示ラベル（value/value）で
      # MATCHESする形に訂正した。
      query = <<~AQL
        SELECT c/name/value AS composition_name,
               o/data[at0001]/items[at0073]/value/value AS diagnosis_label
        FROM EHR e CONTAINS COMPOSITION c
             CONTAINS EVALUATION o[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
        WHERE o/data[at0001]/items[at0073]/value/value
              MATCHES {"疑い", "推定"}
      AQL

      result = OpenehrRails::Aql::Executor.execute(query)

      expect(result.rows).to eq([
        [ "ProblemList", "疑い" ],
        [ "ProblemList", "推定" ]
      ])
    end
  end

  describe "3. CONTAINS nodePredicate（[atNNNN]型）" do
    it "身長値ELEMENT（at0004）を含むCompositionが期待件数（2件）で抽出できる" do
      HeightSeed.seed!(172.0)
      HeightSeed.seed!(175.0)

      query = <<~AQL
        SELECT c/name/value AS composition_name
        FROM EHR e CONTAINS COMPOSITION c
             CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.height.v2]
             CONTAINS ELEMENT el[at0004]
        WHERE EXISTS el/value/magnitude
      AQL

      result = OpenehrRails::Aql::Executor.execute(query)

      expect(result.rows).to eq([
        [ "bmi_calculation" ],
        [ "bmi_calculation" ]
      ])
    end
  end

  describe "4. 日付範囲WHERE（期間絞り込み）" do
    it "認識日時が期間内のCompositionのみ期待件数（1件）で抽出できる" do
      # 実測により訂正: events[at0002]/time は現行AQLエンジンでPathable宣言
      # されておらずALLOWED_TERMINAL_HOPSにも無いため
      # "unsupported path attribute" になる（実測確認、
      # openehr gem lib/openehr/rm/data_structures/history.rb の
      # path_attribute宣言に time が含まれない）。日時属性のWHERE絞り込みは
      # 現行エンジンでは実行不能と判断し、代わりにELEMENT値として保持される
      # DV_DATE_TIMEフィールド（ProblemList at0003「臨床的に認識された日時」、
      # .../value経由）で代替した。ISO8601同士の文字列比較（辞書順=時間順）に
      # 依存している点に注意（将来の型付き比較への移行点）。
      ProblemDiagnosisSeed.seed!(certainty_code: "at0074", recognized_at: "2026-03-15T09:00:00+09:00")
      ProblemDiagnosisSeed.seed!(certainty_code: "at0074", recognized_at: "2026-09-01T09:00:00+09:00")

      query = <<~AQL
        SELECT o/data[at0001]/items[at0003]/value/value AS recognized_at
        FROM EHR e CONTAINS COMPOSITION c
             CONTAINS EVALUATION o[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
        WHERE o/data[at0001]/items[at0003]/value/value >= "2026-01-01T00:00:00"
          AND o/data[at0001]/items[at0003]/value/value < "2026-07-01T00:00:00"
      AQL

      result = OpenehrRails::Aql::Executor.execute(query)

      expect(result.rows).to eq([ [ "2026-03-15T00:00:00Z" ] ])
    end
  end
end
