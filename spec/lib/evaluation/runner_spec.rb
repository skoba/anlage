require "rails_helper"

# 実行器（docs/design/s1-eval-v2-plan.md 2.4）。最初の pin: v1 の 17 問を v2 の枠組みで走らせ、
# spec/lib/tasks/pathcards_eval_spec.rb と同じ前提（4 テンプレートを索引）で同じ集計になる。
RSpec.describe Evaluation::Runner do
  context "現有 4 テンプレートが索引済みの場合" do
    before do
      %w[bmi_calculation ProblemList CardiologyEncounter LabResultReport].each do |fixture_name|
        template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture_name}.opt").read)
        template.pathcards = Opt::PathcardExtractor.call(template).cards
        template.save!
      end
    end

    let(:questions) { Evaluation::Questions.from_v1_seed }
    subject(:run) { described_class.run(questions) }

    it "v1 の 17 問の集計を再現する: Top-1 15/17、Top-3 15/17、完全失敗 2/17、MRR 0.8824（項目の重み #127 で q07 が 1 位に上がった）、intent_tag 別 11/11・4/4・0/2" do
      summary = run.card_summary

      expect(summary).to include(questions: 17, hit_at_1: 15, hit_at_3: 15, complete_failures: 2)
      expect(summary.fetch(:mrr)).to be_within(0.00005).of(0.8824)
      expect(summary.fetch(:by_intent)).to eq(
        "bigram成立想定" => { hits: 11, total: 11 },
        "複合語" => { hits: 4, total: 4 },
        "同義語ギャップ" => { hits: 0, total: 2 }
      )
      expect(run.card_results.reject { |result| result.score.hit_at_3 }.map { |result| result.question.id }).to eq([ "q16", "q18" ])
    end

    # regression pin（R-20261124-15）: rank を持たない問いは全要素が同じ順位として読む。上の集計は rank の導入の前後で同じで、
    # 順位の組を持つ問いは無い
    it "v1 の 17 問は順位の組を持たず、順位遵守の母数は 0、許容の出現も 0" do
      expect(run.card_summary).to include(ranked_questions: 0, order_kept: 0, order_pairs: 0, order_pairs_kept: 0, acceptables: 0)
      expect(run.card_summary.fetch(:recall_at_3)).to be_within(0.00005).of(0.8824)
    end

    # v1 の draft（q21）は R-20261124-15 で v2 の c021 に移したので、draft の扱いは合成した問いで固定する
    it "draft の問いは採点せず一覧に残す" do
      draft = Evaluation::Question.new(id: "d01", kind: :card, status: :draft, query: "収縮期",
                                       expected: [ { archetype_id: "openEHR-EHR-OBSERVATION.blood_pressure.v2", at_code: "at0004" } ])
      run = described_class.run(questions + [ draft ])

      expect(run.drafts.map(&:id)).to eq([ "d01" ])
      expect(run.card_results.map { |result| result.question.id }).not_to include("d01")
      expect(run.card_summary.fetch(:questions)).to eq(17)
    end
  end

  context "aql の問いと保留問" do
    BP_ID = "openEHR-EHR-OBSERVATION.blood_pressure.v2"
    SYSTOLIC = <<~AQL
      SELECT o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude AS systolic
      FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[#{BP_ID}]
      WHERE o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude > 110
    AQL

    let(:aql_question) do
      Evaluation::Question.new(id: "a001", kind: :aql, query: "収縮期血圧が 110 を超える記録", dataset: "demo_initial",
                               reference_aql: SYSTOLIC, expected_rows: [ [ 120.0 ] ])
    end
    let(:specimen_pending) do
      Evaluation::Question.new(id: "c019", kind: :card, status: :pending, query: "検体",
                               expected: [ { archetype_id: "openEHR-EHR-CLUSTER.specimen.v1", at_code: nil } ],
                               pending_until: "CLUSTER.specimen を含む OPT がコーパスに入る")
    end
    let(:story_pending) do
      Evaluation::Question.new(id: "c021", kind: :card, status: :pending, query: "既往歴",
                               expected: [ { archetype_id: "openEHR-EHR-OBSERVATION.story.v1", at_code: "at0004" } ],
                               pending_until: "story を含む OPT がコーパスに入る")
    end

    it "aql の問いは dataset を作ってから採点し、aql_summary に一致・不一致・実行不能の数が出る" do
      run = described_class.run([ aql_question ])

      expect(run.aql_results.map { |result| [ result.question.id, result.score.status ] }).to eq([ [ "a001", :match ] ])
      expect(run.aql_summary).to eq(questions: 1, match: 1, mismatch: 0, unexecutable: 0)
    end

    # S2 の経路（R-20261124-21 の作業列 3）: selection を持つ aql の問いは、ビルダーが組んだ AQL でも採点する
    it "selection を持つ aql の問いは S2 の経路でも採点し、builder_summary に数が出る。selection の無い問いは母数に入らない" do
      bp = { archetype_id: BP_ID, at_code: "at0004" }
      with_selection = Evaluation::Question.new(id: "a901", kind: :aql, query: "収縮期血圧が 110 を超える記録", dataset: "demo_initial",
                                                reference_aql: SYSTOLIC, expected_rows: [ [ 120.0 ] ],
                                                selection: { columns: [ bp ], conditions: [ { card: bp, operator: ">", value: 110 } ] })
      wrong = Evaluation::Question.new(id: "a902", kind: :aql, query: "収縮期血圧が 110 を超える記録", dataset: "demo_initial",
                                       reference_aql: SYSTOLIC, expected_rows: [ [ 120.0 ] ],
                                       selection: { columns: [ bp ], conditions: [ { card: bp, operator: "<", value: 110 } ] })
      run = described_class.run([ aql_question, with_selection, wrong ])

      expect(run.aql_summary).to eq(questions: 3, match: 3, mismatch: 0, unexecutable: 0)
      expect(run.aql_results.map { |result| [ result.question.id, result.builder_score&.status ] })
        .to eq([ [ "a001", nil ], [ "a901", :match ], [ "a902", :mismatch ] ])
      expect(run.builder_summary).to eq(questions: 2, match: 1, mismatch: 1, unexecutable: 0, unbuildable: 0)
    end

    it "保留問は母数に入らず、期待先のアーキタイプがコーパス（active のカード）に現れたものだけ保留解除候補になる" do
      Evaluation::Datasets.build("demo_initial") # jp_referral（story）は含まない
      run = described_class.run([ specimen_pending, story_pending ])

      expect(run.card_summary.fetch(:questions)).to eq(0)
      expect(run.pendings.map(&:id)).to eq([ "c019", "c021" ])
      expect(run.releasable_pendings).to be_empty

      template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/jp_referral.opt").read)
      template.pathcards = Opt::PathcardExtractor.call(template).cards
      template.save!

      expect(described_class.run([ specimen_pending, story_pending ]).releasable_pendings.map(&:id)).to eq([ "c021" ])
    end

    # c021「既往歴」は story と problem_diagnosis の両方が正解（R-20261124-15）。problem_diagnosis は初期状態にあるが、
    # 保留の条件（story がコーパスに入る）は満たしていないので、期待先がすべて現れるまで解除候補にしない
    it "期待先のアーキタイプの一部だけがコーパスにある保留問は、保留解除候補にならない" do
      Evaluation::Datasets.build("demo_initial")
      both = Evaluation::Question.new(id: "c021", kind: :card, status: :pending, query: "既往歴", expected: [
        { archetype_id: "openEHR-EHR-OBSERVATION.story.v1", at_code: "at0004", rank: 1 },
        { archetype_id: "openEHR-EHR-EVALUATION.problem_diagnosis.v1", at_code: nil, rank: 1 }
      ])

      expect(described_class.run([ both ]).releasable_pendings).to be_empty
    end
  end

  # 確定したゴールド v2（R-20261124-15）の実測。ゴールドに追随する spec 側の数字（docs/reports/s1-eval-v2-log.md R12）
  context "確定したゴールド v2 を demo_initial の上で走らせる場合" do
    subject(:run) do
      Evaluation::Datasets.build("demo_initial")
      described_class.run(Evaluation::Questions.from_v2)
    end

    it "card 4 問: Top-1 4/4、recall@3 0.875（c008 の第 2 候補 at0002 が出ない）、負例違反なし、順位遵守 1/1" do
      expect(run.card_summary).to include(questions: 4, hit_at_1: 4, hit_at_3: 4, complete_failures: 0, violations: 0,
                                          ranked_questions: 1, order_kept: 1, order_pairs: 1, order_pairs_kept: 1, acceptables: 0)
      expect(run.card_summary.fetch(:recall_at_3)).to eq(0.875)
    end

    it "aql 5 問は参照 AQL が期待行に一致する（a002 はコード値 at0074 の一致）" do
      expect(run.aql_summary).to eq(questions: 5, match: 5, mismatch: 0, unexecutable: 0)
    end

    it "保留問は c019・c021 の 2 問で、解除候補は無い。draft は S2 の経路の案 3 問（母数外）" do
      expect(run.pendings.map(&:id)).to match_array(%w[c019 c021])
      expect(run.releasable_pendings).to be_empty
      expect(run.drafts.map(&:id)).to match_array(%w[a006 a007 a008])
    end

    it "確定した aql の 5 問は selection を持たないので、S2 の経路の母数は 0（案の確定を待つ）" do
      expect(run.builder_summary).to eq(questions: 0, match: 0, mismatch: 0, unexecutable: 0, unbuildable: 0)
    end
  end
end
