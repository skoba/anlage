require "rails_helper"
require_relative "support/height_seed"
require_relative "support/problem_diagnosis_seed"

RSpec.describe "デモクエリ（フォーム保存経路経由）", type: :request do
  before { select_patient } # skoba/anlage#161: 記録は、患者を選んでから保存する（spec/support/patient_selection.rb）

  describe "1. height不等号クエリ" do
    it "供給済みクエリが期待件数（1件）で実行できる" do
      [ "165.0", "170.0", "180.0" ].each do |height|
        post template_compositions_path(HeightSeed.template.template_id), params: {
          values: {
            "height" => height,
            "body_weight" => "70.0",
            "body_mass_index" => "21.6",
            "body_mass_index_at0013" => "normal"
          }
        }
      end

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
      [ "at0074", "at0075", "at0076" ].each do |certainty_code|
        now = Time.current.iso8601
        post template_compositions_path(ProblemDiagnosisSeed.template.template_id), params: {
          values: {
            "problem_diagnosis_at0002" => "Demo diagnosis (#{certainty_code})",
            "problem_diagnosis_at0077" => now,
            "problem_diagnosis_at0003" => Time.current.iso8601,
            "problem_diagnosis_at0030" => now,
            "problem_diagnosis_at0073" => certainty_code
          }
        }
      end

      # skoba/anlage#33 裁定 B: 傷病名 at0002（外部値集合のみ・DV_TEXT 代替あり = coded_free）は
      # raw を code に詰めた DvCodedText ではなく DV_TEXT として保存される（是正の pin）。
      saved_diagnosis = Composition.order(:id).last.rm_composition.dig("content", 0, "data", "items", 0, "value")
      expect(saved_diagnosis["_type"]).to eq("DV_TEXT")
      expect(saved_diagnosis["value"]).to eq("Demo diagnosis (at0076)")

      # 本来形（2026-11-24、openehr 2.5.0 の openehr-ruby#49 で置き換え）: 表示ラベルではなく
      # コード値（value/defining_code/code_string）で MATCHES する。暫定形はタグ v0.1.0-jcmi46 に残る。
      query = <<~AQL
        SELECT c/name/value AS composition_name,
               o/data[at0001]/items[at0073]/value/defining_code/code_string AS certainty_code,
               o/data[at0001]/items[at0073]/value/value AS certainty_label
        FROM EHR e CONTAINS COMPOSITION c
             CONTAINS EVALUATION o[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
        WHERE o/data[at0001]/items[at0073]/value/defining_code/code_string
              MATCHES {"at0074", "at0075"}
      AQL

      result = OpenehrRails::Aql::Executor.execute(query)

      expect(result.rows).to eq([
        [ "ProblemList", "at0074", "疑い" ],
        [ "ProblemList", "at0075", "推定" ]
      ])
    end
  end

  describe "3. CONTAINS nodePredicate（[atNNNN]型）" do
    it "身長値ELEMENT（at0004）を含むCompositionが期待件数（2件）で抽出できる" do
      [ "172.0", "175.0" ].each do |height|
        post template_compositions_path(HeightSeed.template.template_id), params: {
          values: {
            "height" => height,
            "body_weight" => "70.0",
            "body_mass_index" => "21.6",
            "body_mass_index_at0013" => "normal"
          }
        }
      end

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
    include ActiveSupport::Testing::TimeHelpers

    # 本来形（2026-11-24、openehr 2.5.0 の openehr-ruby#48 で置き換え）: OBSERVATION のイベント時刻
    # （events[at0002]/time）の半開区間で絞る。暫定形（ELEMENT 値の DV_DATE_TIME）はタグ v0.1.0-jcmi46 に残る。
    # イベント時刻は保存した時刻（Opt::CompositionBuilder）。比較は ISO8601 の文字列比較なので、
    # 両辺の書式と UTC オフセットをそろえる（RM グラフからの読み戻しは UTC の "…Z"、上流候補 21 項）。
    it "OBSERVATION のイベント時刻が期間内の Composition のみ期待件数（1件）で抽出できる" do
      [ "2026-03-15T00:00:00Z", "2026-09-01T00:00:00Z" ].each do |measured_at|
        travel_to(Time.zone.parse(measured_at)) do
          post template_compositions_path(HeightSeed.template.template_id), params: {
            values: {
              "height" => "170.0",
              "body_weight" => "70.0",
              "body_mass_index" => "24.2",
              "body_mass_index_at0013" => "normal"
            }
          }
        end
      end

      query = <<~AQL
        SELECT o/data[at0001]/events[at0002]/time/value AS measured_at
        FROM EHR e CONTAINS COMPOSITION c
             CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.height.v2]
        WHERE o/data[at0001]/events[at0002]/time/value >= "2026-01-01T00:00:00Z"
          AND o/data[at0001]/events[at0002]/time/value < "2026-07-01T00:00:00Z"
      AQL

      result = OpenehrRails::Aql::Executor.execute(query)

      expect(result.rows).to eq([ [ "2026-03-15T00:00:00Z" ] ])
    end
  end
end
