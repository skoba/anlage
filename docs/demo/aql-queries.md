# デモ使用AQLクエリ一覧

各クエリは `spec/demo/aql_queries_spec.rb` で全実行され、期待件数と照合される。
クエリ本文の変更はこのファイルへの追記・修正を経て行う（壇上での手打ち編集はしない）。
計画: `docs/design/demo-queries-plan.md`。承認事項1により、現状は案B（暫定シード、
`OpenehrRails::Rm::CompositionCommitter`直接呼び出し。実パイプライン非経由）で
実行している。案A（`openEHR-EHR-OBSERVATION.height.v2`のOPT fixture、CKM/AD経由で
人間依頼中）到着後、シードを差し替える（凍結受入条件に数えられるのは案A差し替え後のみ）。

## 1. height不等号クエリ

- 由来: 医療情報学連合大会チュートリアル、事故再発防止の直接対象（SELECT別名`AS height`の
  WHERE句への消し忘れによる構文エラー事故、`skoba/openehr-ruby#38`参照）
- 状態: **供給済み**（会話記録の原文）
- クエリ:
  ```
  SELECT o/data[at0001]/events[at0002]/data[at0003]/items[at0004]/value/magnitude AS height
  FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.height.v2]
  WHERE o/data[at0001]/events[at0002]/data[at0003]/items[at0004]/value/magnitude > 170
  ```
- シード（案B暫定）: 身長165.0cm/170.0cm/180.0cmの3件を投入
- 期待件数: **1件**（180.0cmのみ。170.0cm自体は`> 170`の境界値のため非該当。実測確認済み: `docs/reports/demo-queries-log.md` R2）

## 2. （候補・意図のみ・原文未供給）openehr 2.3.x新機能クエリ

11/5凍結までに人間からクエリ原文の供給を受け、供給されたものから順次spec化する。以下は
候補の意図のみ（Acceptance criteria裁定3節により、AQL新機能〔LIKE/MATCHES/CONTAINS述語/
混合集計〕から最低1本を含める）:

- **LIKE**: グロブ構文（`*`/`?`、SQLの`%`/`_`ではない）を使った検索クエリ。意図: archetype_id
  やテキストフィールドの部分一致デモ
- **MATCHES**（リテラルリスト）: 値集合に対するマッチング。意図: 複数コードのいずれかに
  一致するレコード検索デモ
- **CONTAINS**（standardPredicate/nodePredicate付き）: `[at0004]`のようなnode predicate付き
  containment。意図: 特定archetypeノード配下の絞り込みデモ
- **混合集計**（集計関数＋非集計列の暗黙GROUP BY）: 意図: 件数・平均値等の集計デモ

原文供給後、本節を書き換えて「供給済み」へ移行し、対応する`it`をspec/demo/へ追加する。
