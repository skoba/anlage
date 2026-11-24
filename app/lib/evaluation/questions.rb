module Evaluation
  # 問いの読み込み。v1 の seed（spec/fixtures/pathcards_eval_seed.yml）はアダプタで読む。
  # ゴールド本体（query／expected／notes）は人間の専有領域なので、ファイルは書き換えず読み方だけを v2 に合わせる
  # （docs/design/s1-eval-v2-plan.md 2.2、判断 D1）。v2 固有の問いは spec/fixtures/evaluation/v2/*.yml。
  module Questions
    class InvalidQuestion < StandardError; end

    V1_SEED = "spec/fixtures/pathcards_eval_seed.yml".freeze
    V2_DIR = "spec/fixtures/evaluation/v2".freeze
    REQUIRED_KEYS = { card: %w[query expected], aql: %w[query dataset reference_aql expected_rows] }.freeze

    module_function

    # v1 の 1 エントリ → kind: card、match: archetype（v1 は archetype_id の一致だけで採点していた）、
    # expected は {archetype_id, at_code} の 1 要素、draft: true → status: draft。
    # match: :card を渡すと同じ問いを at_code まで見て集計できる（情報。pin ではない）。
    def from_v1_seed(path = Rails.root.join(V1_SEED), match: :archetype)
      YAML.load_file(path, permitted_classes: [ Date ]).map do |entry|
        Question.new(
          id: entry.fetch("id"),
          kind: :card,
          status: entry["draft"] ? :draft : :active,
          query: entry.fetch("query"),
          expected: [ { archetype_id: entry.fetch("expected_archetype_id"), at_code: entry["expected_at_code"].presence } ],
          match: match,
          intent_tag: entry["intent_tag"],
          notes: entry["notes"],
          source: path.to_s
        )
      end
    end

    # v2 のディレクトリ配下の *.yml をファイル名順に読む。形式の誤りは InvalidQuestion で止める（黙って母数を変えない）。
    def from_v2(dir = Rails.root.join(V2_DIR))
      Pathname.new(dir).glob("*.yml").sort.flat_map do |path|
        Array(YAML.load_file(path, permitted_classes: [ Date ])).map { |entry| build_v2(entry, path) }
      end
    end

    def build_v2(entry, path)
      id = entry["id"] || raise(InvalidQuestion, "#{path}: id が無い問いがある")
      kind = enum!(id, "kind", entry["kind"], Question::KINDS)
      status = enum!(id, "status", entry.fetch("status", "active"), Question::STATUSES)
      match = enum!(id, "match", entry.fetch("match", "card"), Question::MATCHES)
      missing = REQUIRED_KEYS.fetch(kind).reject { |key| entry.key?(key) }
      raise InvalidQuestion, "#{id}: #{kind} の問いに必須のキー #{missing.join('・')} が無い" if missing.any?

      Question.new(
        id: id, kind: kind, status: status, query: entry.fetch("query"),
        expected: ranked_refs(id, entry["expected"]), match: match, forbidden: card_refs(entry["forbidden"]),
        acceptable: card_refs(entry["acceptable"]),
        intent_tag: entry["intent_tag"], notes: entry["notes"],
        dataset: entry["dataset"], reference_aql: entry["reference_aql"], expected_rows: entry["expected_rows"],
        ordered: entry.fetch("ordered", false), cards: card_refs(entry["cards"]),
        pending_until: entry["pending_until"], source: path.to_s
      )
    end

    def enum!(id, key, value, allowed)
      symbol = value.to_s.to_sym
      return symbol if allowed.include?(symbol)

      raise InvalidQuestion, "#{id}: #{key} は #{allowed.join('／')} のどれか（#{value.inspect}）"
    end

    # expected は rank（1 以上の整数）を持てる。1 問の中で rank の有無を混ぜない（書き忘れか同順位かを推測しない）。
    # rank の無い問いの要素には rank キーを付けない（全要素が同じ順位として採点器が読む）
    def ranked_refs(id, list)
      entries = Array(list)
      ranks = entries.map { |ref| ref["rank"] }
      return card_refs(entries) if ranks.all?(&:nil?)

      unless ranks.all? { |rank| rank.is_a?(Integer) && rank >= 1 }
        raise InvalidQuestion, "#{id}: expected の rank は 1 以上の整数で、付けるなら全要素に付ける（#{ranks.inspect}）"
      end

      card_refs(entries).zip(ranks).map { |ref, rank| ref.merge(rank: rank) }
    end

    def card_refs(list)
      Array(list).map { |ref| { archetype_id: ref.fetch("archetype_id"), at_code: ref["at_code"].presence } }
    end
  end
end
