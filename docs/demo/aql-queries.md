# デモ使用AQLクエリ一覧

各クエリは `spec/demo/aql_queries_spec.rb` で全実行され、期待件数と照合される。
クエリ本文の変更はこのファイルへの追記・修正を経て行う（壇上での手打ち編集はしない）。
計画: `docs/design/demo-queries-plan.md`。**案A（実パイプライン駆動）へ移行済み
（2026-08-23）**。`spec/fixtures/opt/bmi_calculation.opt`（openehr-rails
demo_assets由来、lang=en、`skoba/anlage#5`用途限定。出所詳細はfixture冒頭
コメントおよび`docs/demo/opt-catalog.md`参照）の`openEHR-EHR-OBSERVATION.height.v2`
を使用。`Opt::CompositionBuilder`（フォーム保存経路と同じ構築ロジック）経由で
シードする。ただし2件の回避策（`skoba/anlage#9`、`docs/upstream-candidates.md`
9項）付き——恒久解消まではこの依存を残す。

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
- シード（案A、`spec/demo/support/height_seed.rb`）: 身長165.0cm/170.0cm/180.0cmの3件を投入
- 期待件数: **1件**（180.0cmのみ。170.0cm自体は`> 170`の境界値のため非該当。実測確認済み: `docs/reports/demo-queries-log.md` R2・R3）
- **凍結受入条件に算入可能**（案A差し替え完了。`docs/design/demo-queries-plan.md` 5節）

## 2. MATCHES 値リスト（コード値の複数一致）

- 状態: **供給済み・実測で訂正のうえ採用**
- 意図: WHERE句でMATCHESにリテラルの値リストを与え、複数コードのいずれかに一致するレコードを
  検索するデモ（openehr 2.3.0以降で実行可能になったAQL構文、openehr-rails CHANGELOG
  「MATCHES against a literal value list」）
- **原文からの差分**: at-code（`at0.63`/`at0.64`はプレースホルダ）を`ProblemList.opt`の
  実ローカル値集合（at0073「診断確度」、WP2 TODO 7実測選定。`at0074`=疑い/`at0075`=推定/`at0076`=確定）へ、
  パスを`items[at0002]`→`items[at0073]`（パスカードの`identity.path`実測値）へ差し替えた。
  さらに`value/defining_code/code_string`は現行AQLエンジンの`ALLOWED_TERMINAL_HOPS`
  （openehr gem`lib/openehr/aql/engine/path_evaluator.rb`。`magnitude`/`name`/`value`のみ許可）が
  未対応で`unsupported path attribute`になったため、`value/value`（DvCodedTextの表示ラベル）での
  MATCHESに訂正した（コード自体ではなくラベル文字列でのマッチングになる点に注意）
- クエリ:
  ```
  SELECT c/name/value AS composition_name,
         o/data[at0001]/items[at0073]/value/value AS diagnosis_label
  FROM EHR e CONTAINS COMPOSITION c
       CONTAINS EVALUATION o[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
  WHERE o/data[at0001]/items[at0073]/value/value
        MATCHES {"疑い", "推定"}
  ```
- シード（`spec/demo/support/problem_diagnosis_seed.rb`）: 診断確度at0074/at0075/at0076の3件を投入
- 期待件数: **2件**（at0074「疑い」・at0075「推定」。at0076「確定」は対象外。実測確認済み: `docs/reports/demo-queries-log.md` R4）
- **凍結受入条件に算入可能**

## 3. CONTAINS nodePredicate（`[atNNNN]`型）

- 状態: **供給済み・原文どおり採用（訂正なし）**
- 意図: CONTAINS句にarchetype述語ではなく`[at0004]`のようなnode predicateを与え、特定の
  archetypeノード配下に絞り込むデモ（openehr 2.3.0以降で実行可能。openehr-rails CHANGELOG
  「CONTAINS with a standardPredicate/nodePredicate」）
- **原文からの差分**: 無し。ELEMENTを直接CONTAINS対象にでき、`WHERE EXISTS`も実測で
  問題なく通ることを確認したため、原文をそのまま採用した
- クエリ:
  ```
  SELECT c/name/value AS composition_name
  FROM EHR e CONTAINS COMPOSITION c
       CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.height.v2]
       CONTAINS ELEMENT el[at0004]
  WHERE EXISTS el/value/magnitude
  ```
- シード（`spec/demo/support/height_seed.rb`）: 身長172.0cm/175.0cmの2件を投入
- 期待件数: **2件**（両方ともat0004にmagnitude値を持つため。実測確認済み: `docs/reports/demo-queries-log.md` R4）
- **凍結受入条件に算入可能**

## 4. 日付範囲WHERE（期間絞り込み）

- 状態: **供給済み・実測で訂正のうえ採用**
- 意図: WHERE句で日時フィールドに範囲条件（`>=`/`<`）を与え、期間で絞り込むデモ
- **原文からの差分**: `events[at0002]/time`は現行AQLエンジンでPathable宣言されておらず
  （`openehr` gem `lib/openehr/rm/data_structures/history.rb`のEVENT系`path_attribute`宣言に
  `time`が無い）、`ALLOWED_TERMINAL_HOPS`にも含まれないため`unsupported path attribute`になり、
  **OBSERVATIONの測定時刻というアプローチ自体が現行AQLエンジンでは実行不能**と判明した。
  そのため対象を`ProblemList.opt`のELEMENT値として保持されるDV_DATE_TIMEフィールド
  （at0003「臨床的に認識された日時」、`.../value`経由で到達可能）へ差し替えた。ANDの複数条件は
  実測で問題なく通ったため単一条件への縮約は不要だった。**ISO8601同士の文字列比較（辞書順=時間順）
  に依存している**点に注意（将来の型付き比較への移行点。原文供給時の注記どおり）
- クエリ:
  ```
  SELECT o/data[at0001]/items[at0003]/value/value AS recognized_at
  FROM EHR e CONTAINS COMPOSITION c
       CONTAINS EVALUATION o[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
  WHERE o/data[at0001]/items[at0003]/value/value >= "2026-01-01T00:00:00"
    AND o/data[at0001]/items[at0003]/value/value < "2026-07-01T00:00:00"
  ```
- シード（`spec/demo/support/problem_diagnosis_seed.rb`）: 認識日時2026-03-15（期間内）・2026-09-01（期間外）の2件を投入
- 期待件数: **1件**（期間内の1件のみ。実測確認済み: `docs/reports/demo-queries-log.md` R4）
- **凍結受入条件に算入可能**

---

全4クエリとも供給済み・spec化完了。`bundle exec rspec spec/demo/`がgreenであることが
`docs/design/demo-queries-plan.md` 5節の凍結受入条件。
