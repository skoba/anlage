module Evaluation
  # 問いの読み込み。v1 の seed（spec/fixtures/pathcards_eval_seed.yml）はアダプタで読む。
  # ゴールド本体（query／expected／notes）は人間の専有領域なので、ファイルは書き換えず読み方だけを v2 に合わせる
  # （docs/design/s1-eval-v2-plan.md 2.2、判断 D1）。v2 固有の問いは spec/fixtures/evaluation/v2/*.yml。
  module Questions
    class InvalidQuestion < StandardError; end

    V1_SEED = "spec/fixtures/pathcards_eval_seed.yml".freeze
    V2_DIR = "spec/fixtures/evaluation/v2".freeze
    REQUIRED_KEYS = { card: %w[query expected], aql: %w[query dataset expected_rows] }.freeze

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

      reference_aqls = reference_aqls(id, entry) if kind == :aql
      expected = ranked_refs(id, entry["expected"])
      forbidden = card_refs(entry["forbidden"])
      if kind == :card && expected.empty? && forbidden.empty?
        raise InvalidQuestion, "#{id}: card の問いに expected も forbidden も無い（負例だけの問いは forbidden が要る）"
      end

      Question.new(
        id: id, kind: kind, status: status, query: entry.fetch("query"),
        expected: expected, match: match, forbidden: forbidden,
        acceptable: card_refs(entry["acceptable"]),
        intent_tag: entry["intent_tag"], notes: entry["notes"],
        dataset: entry["dataset"], reference_aql: entry["reference_aql"], reference_aqls: reference_aqls,
        expected_rows: entry["expected_rows"],
        ordered: entry.fetch("ordered", false), cards: card_refs(entry["cards"]),
        pending_until: entry["pending_until"], source: path.to_s, selection: selection(id, entry["selection"])
      )
    end

    # aql の問いは、参照 AQL（reference_aql）か、版ごとの参照 AQL（reference_aqls。アーキタイプ ID → AQL）のどちらか 1 つを持つ
    def reference_aqls(id, entry)
      single = entry.key?("reference_aql")
      multiple = entry.key?("reference_aqls")
      raise InvalidQuestion, "#{id}: aql の問いに必須のキー reference_aql（または reference_aqls）が無い" unless single || multiple
      raise InvalidQuestion, "#{id}: reference_aql と reference_aqls は、どちらか 1 つだけを書く" if single && multiple
      return nil if single

      aqls = entry["reference_aqls"]
      unless aqls.is_a?(Hash) && aqls.any? && aqls.values.all? { |aql| aql.is_a?(String) && aql.present? }
        raise InvalidQuestion, "#{id}: reference_aqls は「アーキタイプ ID: AQL」の表で書く（#{aqls.inspect}）"
      end

      aqls.transform_keys(&:to_s)
    end

    # S2 の経路の入力（クエリビルダーの選択）。カードは {archetype_id, at_code} で指す。値はそのまま渡す（検査はビルダーとリンタ）
    def selection(id, raw)
      return nil if raw.nil?

      columns = card_refs(raw["columns"])
      raise InvalidQuestion, "#{id}: selection に columns（表示する項目）が無い" if columns.empty?

      conditions = Array(raw["conditions"]).map { |condition| selection_condition(id, condition) }
      parsed = { columns: columns, conditions: conditions, template_id: raw["template_id"] ? true : false }
      raw["across_versions"] ? parsed.merge(across_versions: true) : parsed
    end

    # 条件は { card, operator, value, include_missing } か、どちらかを満たす { any: [条件, …] }（docs/design/s1-eval-v2-plan.md 8.4）
    def selection_condition(id, condition)
      if condition.is_a?(Hash) && condition.key?("any")
        members = condition["any"]
        raise InvalidQuestion, "#{id}: selection の any は条件の配列で書く（#{members.inspect}）" unless members.is_a?(Array)

        return { any: members.map { |member| selection_condition(id, member) } }
      end
      unless condition.is_a?(Hash) && condition["card"].is_a?(Hash) && condition["operator"]
        raise InvalidQuestion, "#{id}: selection の条件には card と operator が要る（#{condition.inspect}）"
      end

      value = condition["value"]
      value = value.transform_keys(&:to_sym) if value.is_a?(Hash)
      parsed = { card: card_refs([ condition["card"] ]).first, operator: condition["operator"].to_s, value: value }
      condition["include_missing"] ? parsed.merge(include_missing: true) : parsed
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
