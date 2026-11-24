### Added

- 同じアーキタイプの複数ルートを区別する（`skoba/anlage#117`）。field 名が衝突するときは、文書順で 2 つめ以降に `_2`・`_3` を付ける
  （例: 紹介先医療機関の名称は `organisation_at0001_2`）。項目は属するルート（インスタンス）のテンプレート上の名前でまとまり、
  保存すると別々の CLUSTER・EVALUATION に入る
- jp_referral（診療情報提供書）の帳票が保存できるようになった

### Fixed

- 紹介先医療機関の項目に「紹介元医療機関」の名前が付いていた（同じ path の最初のルートの名前を引いていた）

利用者に見える変更: あり（jp_referral の帳票に保存ボタンが出る）。登録済みの jp_referral の `web_template` は登録時のまま（閲覧専用）。
保存できるようにするには `rake templates:rebuild_web_template`（セッションは実行していない）。
