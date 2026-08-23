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

## 2. MATCHES 値リスト（コード値の複数一致）

- 状態: **意図のみ・原文未供給**
- 意図: WHERE句でMATCHESにリテラルの値リストを与え、複数コードのいずれかに一致するレコードを
  検索するデモ（openehr 2.3.0以降で実行可能になったAQL構文、`docs/upstream-candidates.md`等
  参照。openehr-rails CHANGELOG「MATCHES against a literal value list」）
- クエリ原文: 人間供給待ち
- 期待件数: 原文供給後にシード設計とあわせて確定

## 3. CONTAINS nodePredicate（`[atNNNN]`型）

- 状態: **意図のみ・原文未供給**
- 意図: CONTAINS句にarchetype述語ではなく`[at0004]`のようなnode predicateを与え、特定の
  archetypeノード配下に絞り込むデモ（openehr 2.3.0以降で実行可能。openehr-rails CHANGELOG
  「CONTAINS with a standardPredicate/nodePredicate」）
- クエリ原文: 人間供給待ち
- 期待件数: 原文供給後にシード設計とあわせて確定

## 4. 日付範囲WHERE（期間絞り込み）

- 状態: **意図のみ・原文未供給**
- 意図: WHERE句で日時フィールドに範囲条件（`>=`/`<=`等）を与え、期間で絞り込むデモ
- クエリ原文: 人間供給待ち
- 期待件数: 原文供給後にシード設計とあわせて確定

---

原文供給後、該当節を書き換えて「供給済み」へ移行し、対応する`it`を`spec/demo/`へ追加する
（`docs/design/demo-queries-plan.md` 6節のTDD手順どおり、1クエリ=1コミット）。
