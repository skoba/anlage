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

    it "v1 の 17 問の集計を再現する: Top-1 14/17、Top-3 15/17、完全失敗 2/17、MRR 0.8529、intent_tag 別 11/11・4/4・0/2" do
      summary = run.card_summary

      expect(summary).to include(questions: 17, hit_at_1: 14, hit_at_3: 15, complete_failures: 2)
      expect(summary.fetch(:mrr)).to be_within(0.00005).of(0.8529)
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

    it "draft の問いは採点せず一覧に残す（q21）" do
      expect(run.drafts.map(&:id)).to eq([ "q21" ])
      expect(run.card_results.map { |result| result.question.id }).not_to include("q21")
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
  end
end
