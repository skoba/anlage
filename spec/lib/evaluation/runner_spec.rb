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
    # 字面だけの検索（別名表を使わない）。別名表を入れる前の数字の pin を、そのまま保つ
    subject(:run) { described_class.run(questions, aliases: Opt::SearchAliases.none) }

    it "字面だけ（別名表なし）で v1 の 17 問の集計を再現する: Top-1 15/17、Top-3 15/17、完全失敗 2/17、MRR 0.8824（項目の重み #127 で q07 が 1 位に上がった）、intent_tag 別 11/11・4/4・0/2" do
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

    # 別名表（skoba/anlage#152、R-20261125-8）を使うと、字面で届かなかった q16「BMI」と q18「既往」が当たる。
    # この 2 問は表にある語の問いで、効果の数字には入れない。表に無い語の 15 問は、字面だけのときと同じ
    it "別名表を使うと Top-1 17/17。内訳は、表にある語の 2 問（q16・q18）が 2/2、表に無い語の 15 問が 15/15（字面だけのときと同じ問いが当たる）" do
      with_table = described_class.run(questions)

      expect(with_table.card_summary).to include(questions: 17, hit_at_1: 17, hit_at_3: 17, complete_failures: 0, violations: 0)
      expect(with_table.alias_split).to eq(in_table: { questions: 2, hit_at_1: 2, hit_at_3: 2, ids: %w[q16 q18] },
                                           out_of_table: { questions: 15, hit_at_1: 15, hit_at_3: 15, ids: questions.map(&:id) - %w[q16 q18] })
      unchanged = ->(result) { [ result.question.id, result.score.rank ] }
      expect(with_table.card_results.reject { |result| %w[q16 q18].include?(result.question.id) }.map(&unchanged))
        .to eq(run.card_results.reject { |result| %w[q16 q18].include?(result.question.id) }.map(&unchanged))
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
    # 負例だけの問い（docs/design/s1-eval-v2-plan.md 9 節、R-20261125-7）。この索引の「診断」は problem_diagnosis の 6 枚に当たり、
    # 1 位が at0002、2 位が at0073、4 位が at0003。「BMI判定」は body_mass_index at0013 が 1 位。「脈拍」は 1 枚も当たらない
    describe "負例だけの問い" do
      def negative(id, query, forbidden)
        Evaluation::Question.new(id: id, kind: :card, query: query, expected: [], forbidden: forbidden)
      end

      let(:pd) { "openEHR-EHR-EVALUATION.problem_diagnosis.v1" }
      let(:negatives) do
        [ negative("n1", "BMI判定", [ { archetype_id: "openEHR-EHR-OBSERVATION.body_mass_index.v2", at_code: nil } ]),
          negative("n2", "診断", [ { archetype_id: pd, at_code: "at0003" } ]),
          negative("n3", "脈拍", [ { archetype_id: pd, at_code: nil } ]) ]
      end

      it "regression pin: 負例だけの問いを混ぜても、card の集計と問いごとの結果は、もとの 17 問だけのときと同じ" do
        mixed = described_class.run(questions + negatives, aliases: Opt::SearchAliases.none)

        expect(mixed.card_summary).to eq(run.card_summary)
        expect(mixed.card_results.map { |result| [ result.question.id, result.score.to_h ] })
          .to eq(run.card_results.map { |result| [ result.question.id, result.score.to_h ] })
      end

      it "負例だけの問いは card_results に入らず negative_results に入る。負例が top-3 に出た問いだけを違反に数える" do
        mixed = described_class.run(questions + negatives)

        expect(mixed.negative_results.map { |result| result.question.id }).to eq(%w[n1 n2 n3])
        expect(mixed.negative_summary).to eq(questions: 3, violations: 1)
        expect(mixed.negative_results.map { |result| result.score.violations.size }).to eq([ 1, 0, 0 ])
      end

      it "負例だけの問いが無ければ、negative_summary は 0 問" do
        expect(run.negative_summary).to eq(questions: 0, violations: 0)
      end

      it "draft の負例だけの問いは採点せず、draft の一覧に残す" do
        draft = Evaluation::Question.new(id: "n9", kind: :card, status: :draft, query: "肥満度", expected: [],
                                         forbidden: [ { archetype_id: "openEHR-EHR-OBSERVATION.body_mass_index.v2", at_code: nil } ])
        mixed = described_class.run(questions + [ draft ])

        expect(mixed.negative_results).to be_empty
        expect(mixed.drafts.map(&:id)).to eq([ "n9" ])
      end
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

    # 2026-11-25 に 9 問を足した（R-20261125-7）。段 D・E の before になる数字（docs/reports/s1-eval-v2-log.md R18）
    it "字面だけ（別名表なし）の card 13 問: Top-1 8/13、Top-3 10/13、完全失敗 2/13（c022「病名」・c023「疾患名」）、負例違反なし、順位遵守 1/1、許容の出現 1/13（c026）" do
      Evaluation::Datasets.build("demo_initial")
      lexical = described_class.run(Evaluation::Questions.from_v2.reject(&:aql?), aliases: Opt::SearchAliases.none)

      expect(lexical.card_summary).to include(questions: 13, hit_at_1: 8, hit_at_3: 10, complete_failures: 2, violations: 0,
                                              ranked_questions: 1, order_kept: 1, order_pairs: 1, order_pairs_kept: 1, acceptables: 1)
      expect(lexical.card_summary.fetch(:mrr)).to be_within(0.00005).of(0.6987)
      expect(lexical.card_summary.fetch(:recall_at_3)).to be_within(0.00005).of(0.7308)
      expect(lexical.card_results.select { |result| result.score.complete_failure }.map { |result| result.question.id }).to eq(%w[c022 c023])
      expect(lexical.card_results.reject { |result| result.score.hit_at_1 }.map { |result| result.question.id })
        .to eq(%w[c022 c023 c027 c029 c030])
    end

    # 別名表（skoba/anlage#152）。表にある語の問いは c015・c022・c023。表に無い語の 10 問は、字面だけのときと同じ（7/10、9/10）
    it "別名表を使うと card 13 問は Top-1 10/13、Top-3 12/13、完全失敗 0/13。表に無い語の 10 問は Top-1 7/10、Top-3 9/10 のまま" do
      expect(run.card_summary).to include(questions: 13, hit_at_1: 10, hit_at_3: 12, complete_failures: 0, violations: 0,
                                          ranked_questions: 1, order_kept: 1, acceptables: 1)
      expect(run.card_summary.fetch(:mrr)).to be_within(0.00005).of(0.8526)
      expect(run.alias_split).to include(in_table: { questions: 3, hit_at_1: 3, hit_at_3: 3, ids: %w[c015 c022 c023] })
      expect(run.alias_split.fetch(:out_of_table)).to include(questions: 10, hit_at_1: 7, hit_at_3: 9)
      expect(run.card_results.reject { |result| result.score.hit_at_1 }.map { |result| result.question.id }).to eq(%w[c027 c029 c030])
    end

    it "足す前からの card 4 問（c008・c010・c014・c015）の結果は変わらない: 4 問とも 1 位、負例違反なし" do
      original = run.card_results.select { |result| %w[c008 c010 c014 c015].include?(result.question.id) }

      expect(original.map { |result| result.score.rank }).to eq([ 0, 0, 0, 0 ])
      expect(original.sum { |result| result.score.recall_at_3 } / 4).to eq(0.875)
      expect(original.flat_map { |result| result.score.violations }).to be_empty
    end

    it "aql 5 問は参照 AQL が期待行に一致する（a002 はコード値 at0074 の一致）" do
      expect(run.aql_summary).to eq(questions: 5, match: 5, mismatch: 0, unexecutable: 0)
    end

    # c033「脈拍」は、期待先のアーキタイプ（heart_rate-pulse.v1）が demo_initial の索引にあるので「保留解除候補」の印が付く。
    # 保留の理由は「日本語訳が済んでいない」で、索引に入ったことでは解けない（印は当てにならない。ログ R18 に書いた）
    it "保留問は c019・c021・c033 の 3 問。解除候補の印は c033 にだけ付く。draft は案 3 問（母数外）" do
      expect(run.pendings.map(&:id)).to match_array(%w[c019 c021 c033])
      expect(run.releasable_pendings.map(&:id)).to eq(%w[c033])
      expect(run.drafts.map(&:id)).to match_array(%w[a006 a007 a008])
    end

    # c034「肥満度」（R-20261125-11 で active）。いまの検索では 1 枚も当たらないので、負例は出ない。card 13 問の集計には入らない
    it "負例だけの問いは c034 の 1 問で、負例が上位に出た問いは 0。intent_tag 別は bigram成立想定 5/5、複合語 5/5、同義語ギャップ 2/3" do
      expect(run.negative_results.map { |result| result.question.id }).to eq(%w[c034])
      expect(run.negative_summary).to eq(questions: 1, violations: 0)
      expect(run.negative_results.first.results).to eq([])
      expect(run.card_summary.fetch(:by_intent)).to eq("bigram成立想定" => { hits: 5, total: 5 }, "複合語" => { hits: 5, total: 5 },
                                                       "同義語ギャップ" => { hits: 2, total: 3 })
    end

    it "確定した aql の 5 問は selection を持たないので、S2 の経路の母数は 0（案の確定を待つ）" do
      expect(run.builder_summary).to eq(questions: 0, match: 0, mismatch: 0, unexecutable: 0, unbuildable: 0)
    end
  end
end
