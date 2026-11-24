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

    it "draft の問いは採点せず一覧に残す（q21）" do
      expect(run.drafts.map(&:id)).to eq([ "q21" ])
      expect(run.card_results.map { |result| result.question.id }).not_to include("q21")
    end
  end
end
