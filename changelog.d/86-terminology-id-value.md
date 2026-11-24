### Fixed

- フォームから保存した Composition の `terminology_id` が値を持つようになった（言語は `ISO_639-1`、地域は `ISO_3166-1`、
  文字コードは `IANA_character-sets`、category は `openehr`、選択肢は `local` または OPT の用語体系）。
  これまでは `{"_type":"TERMINOLOGY_ID"}` で、値が無かった（`skoba/anlage#86`）

利用者に見える変更: あり（保存される Composition の形が変わる）。既に保存済みの記録は変えない。
