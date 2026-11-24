### Fixed

- フォームから保存した Composition のルートが、COMPOSITION アーキタイプの ID を `archetype_node_id` に持ち、
  `archetype_details`（archetype_id・template_id・rm_version）を持つようになった。これまでは
  `archetype_node_id` に template_id が入り、`archetype_details` が無かった（`skoba/anlage#54`）
- その結果、RM グラフ（`openehr_rm_compositions`）の `template_id` 列に、フォーム経路の記録でも template_id が入る
- Composition の JSON をドロップしたときのテンプレートの照合は、`archetype_details.template_id` を見る。
  以前の形（ルートの `archetype_node_id` が template_id）も引き続き受け付ける

利用者に見える変更: あり（保存される Composition の形が変わる）。既に保存済みの記録は変えない。
開発機の保存済みデータを新しい形にそろえるには `rake demo:reset` を使う（セッションは実行していない）。
