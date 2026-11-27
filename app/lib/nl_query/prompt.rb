require "digest"

module NlQuery
  # LLM に渡す文を組む（docs/design/s4-nl-aql-plan.md 4.2・4.3）。アダプタ（Llm::Adapter）には、ここで組んだ
  # instructions（決まった指示文）と input（候補のカードの行と、問い）だけが渡る。
  #
  # カードから取る項目は、下の card_line に書いた 7 つだけ（許可した項目だけを送る作り）。パス、アーキタイプの ID、at-code、
  # 説明、bindings、provenance は読まない。LLM はカードを番号で指し、番号からカードに戻すのは SelectionParser。
  class Prompt
    KIND_NAMES = { number: "数値", code: "値集合", date: "日時", text: "文字列" }.freeze
    # 値集合の表示名を送ってよいコード: アーキタイプの中の用語（at-code）だけ。外の用語のコードの表示名は送らない
    LOCAL_CODE = /\Aat\d+(\.\d+)*\z/

    INSTRUCTIONS = <<~TEXT.freeze
      あなたは、臨床の記録を引く問い合わせの組み立てを手伝います。
      利用者の問い（日本語）と、候補の項目の一覧を渡します。問いに答えるために、どの項目を表示し、どの項目にどの条件を付けるかを、JSON で返してください。

      候補の項目は、1 行に 1 つです。
      番号 | 項目名 | 項目が入っている区分 | 型 | 値集合の値（型が値集合のとき） | 単位 | テンプレート

      返す JSON の形:
      {"columns": [番号, ...], "conditions": [条件, ...], "template_id": false, "across_versions": false, "reason": null}

      - columns: 表示する項目の番号。問いが求めている項目だけを入れる
      - conditions: 絞り込みの条件。無ければ空の配列。すべての条件を満たす記録が当たる
      - template_id: 問いが、記録の出所（どの文書・テンプレートか）も求めているときだけ true
      - across_versions: 問いが、アーキタイプの版をまたいで引くことを求めているときだけ true
      - 項目は、番号だけで指す。一覧に無い番号、項目名、パス、コードを書かない

      条件の形は、項目の型で決まる。
      - 数値: {"card": 番号, "operator": ">" か ">=" か "<" か "<=" か "=", "value": 数}
      - 数値（範囲の外）: {"card": 番号, "operator": "OUTSIDE", "value": {"low": 下限, "high": 上限}}
      - 値集合: {"card": 番号, "operator": "MATCHES", "value": ["値集合の値", ...]}
        値は、一覧にある値集合の値の文字のまま書く。未記入の記録も含めるときは "include_missing": true を足す
      - 日時: {"card": 番号, "operator": "BETWEEN", "value": {"from": "2025-01-01", "to": "2026-01-01"}}
        from 以上、to 未満。片方だけでもよい
      - 文字列: {"card": 番号, "operator": "=", "value": "文字列"}（一致）
        {"card": 番号, "operator": "CONTAINS", "value": "文字列"}（含む）
        {"card": 番号, "operator": "MATCHES", "value": ["文字列", ...]}（いずれかに一致）
      - どちらかを満たす: {"any": [条件, 条件, ...]}（2 つ以上。入れ子にしない）

      値は、問いの文から抜き出す。問いに無い値を作らない。
      1 回の問い合わせで使えるのは、同じ区分（同じ種類の記録）の項目だけ。
      候補の項目では問いに答えられないときは、columns と conditions を空にして、reason に理由を 1 文で書く。
      JSON だけを返す。説明の文を付けない。
    TEXT

    attr_reader :question, :cards

    def initialize(question:, cards:)
      @question = question.to_s.strip
      @cards = Array(cards)
    end

    def instructions = INSTRUCTIONS

    def card_lines
      @cards.each_with_index.map { |card, index| card_line(index + 1, card) }
    end

    def input
      "候補の項目:\n#{card_lines.join("\n")}\n\n問い: #{clean(@question)}\n"
    end

    # 送る文（指示文と入力）の指紋。測定の記録と、記録した応答の鍵に使う
    def sha256
      Digest::SHA256.hexdigest("#{instructions}\n#{input}")
    end

    private

    def card_line(number, card)
      kind = QueryBuilder::Builder.kind(card)
      [ number,
        card.dig("semantics", "labels", 0, "text"),
        Array(card.dig("semantics", "container_labels")).map { |container| container["text"] }.join("／"),
        KIND_NAMES.fetch(kind),
        value_labels(card).join("、"),
        card.dig("constraints", "value", "units"),
        card.dig("identity", "template_id") ].map { |field| clean(field) }.join(" | ")
    end

    def value_labels(card)
      QueryBuilder::Builder.code_list(card).select { |entry| entry["code"].to_s.match?(LOCAL_CODE) }.map { |entry| entry["label"] }
    end

    # 1 枚を 1 行に保つ: 区切りの文字と改行を、空白に置き換える
    def clean(field)
      field.to_s.gsub(/[|\r\n]+/, " ").squeeze(" ").strip
    end
  end
end
