- 自然言語から AQL（S4）の段 1: LLM に渡す文を組む部品、LLM の応答をクエリビルダーの選択に直して検査する部品、
  説明の文を組む部品（`NlQuery::Prompt`・`SelectionParser`・`Explanation`。`skoba/anlage#224`）。
  利用者に見える変更: なし（部品だけ。画面からは、まだ呼ばれない。LLM も呼ばない）
