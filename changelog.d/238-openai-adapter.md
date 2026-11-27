- 文で問う（自然言語から AQL）に、OpenAI のアダプタを足した（`skoba/anlage#238`）。gem は足していない（標準の HTTP で呼ぶ）。
  **既定はオフ**。`ANLAGE_LLM=openai`、`ANLAGE_LLM_MODEL`、`OPENAI_API_KEY` の 3 つがそろったときだけ、OpenAI の API を呼ぶ。
  接続先は `ANLAGE_LLM_BASE_URL` で変えられる（同じ形の口を持つサーバー）。実際の API は、まだ呼んで確かめていない。
  利用者に見える変更: あり（環境変数を設定すると、クエリビルダーの「文で問う」が OpenAI の API を呼ぶ。設定しなければ、これまでどおり）
