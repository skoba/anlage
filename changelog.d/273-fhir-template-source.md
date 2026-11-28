- Add: 記録を FHIR の Observation と Condition で読める（`/openehr/fhir/Observation`・`/openehr/fhir/Condition`、`subject` で絞る）（Refs #273、Refs R-20261127-30・R-20261128-1）。利用者に見える変更: あり（API）。
  openehr-rails 0.14.1 の `OpenehrRails::Fhir.template_source` に、動いているテンプレート（template_id ごとに 1 つ）を渡した。既知の制限 19 を解消にし、facade が記録に無い値を置くところを 24 に書いた。
  Postman のコレクションに Observation の検索と 1 件、Condition の検索を戻した（台本 I8〜I10）。既知の制限 23（部分的な日時）を 0.14.1 で測り直した（月までの値も保存できる。書かれた精度は残らない）
