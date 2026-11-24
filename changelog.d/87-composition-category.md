### Fixed

- フォームから保存した Composition の `category` が、`value` に表示（`event`）、`code_string` にコード（`433`）を
  持つようになった。これまでは逆に入っていた（`skoba/anlage#87`）
- OPT が `category` を 1 つのコードに絞っていれば、設定の既定値ではなく OPT のコードを使う
  （登録時に `web_template["category_code"]` に入れる）

利用者に見える変更: あり（保存される Composition の形が変わる）。既に保存済みの記録は変えない。
