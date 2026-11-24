### Added

- `Opt::CompositionBuilder` が INSTRUCTION を組む。ACTIVITY（description の ITEM_TREE、`action_archetype_id` は `/.*/`、timing なし）と、
  protocol を持つ。narrative は、入力された要素を文書順に「ラベル: 値」で「；」でつないで作る（案 B、R-20261124-14）（`skoba/anlage#30`）
- 多段の埋め込み CLUSTER（例: 紹介元医療機関 → 住所）を、それぞれのルートの名前で組む

利用者に見える変更: いまは無い（INSTRUCTION を持つ jp_referral は、field 名の衝突〔C〕のため閲覧専用のまま。表示される理由から
「INSTRUCTION は未対応」が消える）。
