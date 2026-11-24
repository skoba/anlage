### Added

- テンプレートの詳細画面（`GET /templates/:template_id`）。template_id、版、帳票に保存できるか（閲覧専用なら理由）、
  項目数、パスカードの枚数が見られる。一覧のカードの「詳細」から開く（`skoba/anlage#98`）
- 版の履歴。同じ template_id の版が新しい順に並び、置き換えられた版の詳細
  （`GET /templates/:template_id/versions/:version`）も開ける

利用者に見える変更: あり（画面が 1 つ増え、URL が 2 つ増える）。既存の URL と画面は、カードのリンクが 1 つ増えるだけ。
