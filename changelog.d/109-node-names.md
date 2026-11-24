### Changed

- フォームから保存した Composition のノードの名前を、テンプレート（OPT）の用語から取るようにした。
  ENTRY はそのルートのテンプレート上の名前（例: `problem_diagnosis` → 「プロブレム・診断」、jp_referral では「傷病名」）、
  HISTORY・EVENT・ITEM_TREE はそのノードの用語（例: `history` → 「Event Series」）（`skoba/anlage#109`）
- COMPOSITION の名前は変えていない（OPT の concept のまま）

利用者に見える変更: あり（保存される Composition の形が変わる。カルテ記録の canonical JSON と、AQL で `name/value` を引いたときの値）。
既に保存済みの記録と、登録済みのテンプレート（`web_template` は登録時のまま）は変えない。登録済みのテンプレートで
新しい名前を使うには `rake templates:rebuild_web_template`（セッションは実行していない）。
