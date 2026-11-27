- 文で問う（自然言語から AQL）に、Claude API のアダプタを足した（段 4。`skoba/anlage#234`）。gem `anthropic` を足した（起動のときには読み込まない）。
  **既定はオフ**。`ANLAGE_LLM=anthropic`、`ANLAGE_LLM_MODEL`、`ANTHROPIC_API_KEY` の 3 つがそろったときだけ、外の API を呼ぶ。
  1 日の回数の上限は `ANLAGE_LLM_DAILY_CALL_LIMIT`（既定 100）。README と `docs/nl-query.md` に、オンにする方法と、費用がかかることを書いた。
  実際の API は、まだ呼んで確かめていない（偽のクライアントの spec だけ）。
  利用者に見える変更: あり（環境変数を設定すると、クエリビルダーの「文で問う」が外の API を呼ぶ。設定しなければ、これまでどおり）
