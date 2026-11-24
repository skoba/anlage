### Added

- `Opt::CompositionBuilder` が、SECTION 配下の ENTRY（EVALUATION・OBSERVATION・ADMIN_ENTRY）を、
  SECTION（archetype_node_id・テンプレート上の名前・archetype_details 付き）の `items` に入れて組む（`skoba/anlage#80`）
- `Opt::CompositionReader` と `Opt::RmCompositionCommitter` が、SECTION の中の ENTRY を辿る
- `web_template` に `section_labels`（SECTION ルートの path → テンプレート上の名前）を足した

### Changed

- 帳票の保存可否（`form_capability`）は「テンプレートのすべての field を正しく組めるときだけ保存可能」と判定する。
  builder が組めないクラスの entry（INSTRUCTION など）が 1 つでもあるとき、また複数の field で名前が衝突するときは、
  閲覧専用になる。理由が複数あれば `; ` でつないで表示する

利用者に見える変更: 登録済みのテンプレートには無い（jp_referral は閲覧専用のまま。表示される理由の文が変わる。
登録済みの `web_template` は登録時のまま）。SECTION を持ち、衝突も未対応クラスも無いテンプレートを
新しく登録すると、保存できるようになる。
