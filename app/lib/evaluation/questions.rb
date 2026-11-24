module Evaluation
  # 問いの読み込み。v1 の seed（spec/fixtures/pathcards_eval_seed.yml）はアダプタで読む。
  # ゴールド本体（query／expected／notes）は人間の専有領域なので、ファイルは書き換えず読み方だけを v2 に合わせる
  # （docs/design/s1-eval-v2-plan.md 2.2、判断 D1）。
  module Questions
    module_function

    # v1 の 1 エントリ → kind: card、match: archetype（v1 は archetype_id の一致だけで採点していた）、
    # expected は {archetype_id, at_code} の 1 要素、draft: true → status: draft。
    def from_v1_seed(path)
      YAML.load_file(path, permitted_classes: [ Date ]).map do |entry|
        Question.new(
          id: entry.fetch("id"),
          kind: :card,
          status: entry["draft"] ? :draft : :active,
          query: entry.fetch("query"),
          expected: [ { archetype_id: entry.fetch("expected_archetype_id"), at_code: entry["expected_at_code"].presence } ],
          match: :archetype,
          intent_tag: entry["intent_tag"],
          notes: entry["notes"],
          source: path.to_s
        )
      end
    end
  end
end
