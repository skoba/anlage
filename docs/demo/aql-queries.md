# デモ使用AQLクエリ一覧

各クエリは `spec/demo/aql_queries_spec.rb` で全実行され、期待件数と照合される。
クエリ本文の変更はこのファイルへの追記・修正を経て行う（壇上での手打ち編集はしない）。
計画: `docs/design/demo-queries-plan.md`。**案A（実パイプライン駆動）へ移行済み
（2026-08-23）**。`spec/fixtures/opt/bmi_calculation.opt`（openehr-rails
demo_assets由来、lang=en、`skoba/anlage#5`用途限定。出所詳細はfixture冒頭
コメントおよび`docs/demo/opt-catalog.md`参照）の`openEHR-EHR-OBSERVATION.height.v2`
を使用。4クエリ全てで実際のフォーム保存経路
（`POST /compositions/:template_id`）からCompositionを保存してAQL照会する。

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
- フォームPOST: 身長165.0cm/170.0cm/180.0cmの3件を投入
- 期待件数: **1件**（180.0cmのみ。170.0cm自体は`> 170`の境界値のため非該当。実測確認済み: `docs/reports/demo-queries-log.md` R2・R3）
- **凍結受入条件に算入可能**（案A差し替え完了。`docs/design/demo-queries-plan.md` 5節）

## 2. MATCHES 値リスト（コード値の複数一致）

- 状態: **本来形に置き換え済み**（2026-11-24。openehr 2.5.0 でコード値の終端ホップ
  `defining_code/code_string` に届くようになったため。[openehr-ruby#49](https://github.com/skoba/openehr-ruby/issues/49)、
  `docs/upstream-candidates.md` 10項。表示ラベルで絞る暫定形はタグ `v0.1.0-jcmi46` に残る）
- 意図: WHERE句でMATCHESにリテラルの値リストを与え、複数コードのいずれかに一致するレコードを
  検索するデモ（openehr 2.3.0以降で実行可能になったAQL構文、openehr-rails CHANGELOG
  「MATCHES against a literal value list」）
- at-code は `ProblemList.opt` の実ローカル値集合（at0073「診断確度」。`at0074`=疑い/`at0075`=推定/`at0076`=確定）、
  パスはパスカードの `identity.path` の実測値
- クエリ:
  ```
  SELECT c/name/value AS composition_name,
         o/data[at0001]/items[at0073]/value/defining_code/code_string AS certainty_code,
         o/data[at0001]/items[at0073]/value/value AS certainty_label
  FROM EHR e CONTAINS COMPOSITION c
       CONTAINS EVALUATION o[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
  WHERE o/data[at0001]/items[at0073]/value/defining_code/code_string
        MATCHES {"at0074", "at0075"}
  ```
- フォームPOST: 診断確度at0074/at0075/at0076の3件を投入
- 期待件数: **2件**（at0074「疑い」・at0075「推定」。at0076「確定」は対象外。実測: `docs/reports/m2-log.md` R5）
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
- フォームPOST: 身長172.0cm/175.0cmの2件を投入
- 期待件数: **2件**（両方ともat0004にmagnitude値を持つため。実測確認済み: `docs/reports/demo-queries-log.md` R4）
- **凍結受入条件に算入可能**

## 4. 日付範囲WHERE（期間絞り込み）

- 状態: **本来形に置き換え済み**（2026-11-24。openehr 2.5.0 で OBSERVATION のイベント時刻 `events/time` に
  届くようになったため。[openehr-ruby#48](https://github.com/skoba/openehr-ruby/issues/48)、
  `docs/upstream-candidates.md` 11項。ELEMENT 値の DV_DATE_TIME で絞る暫定形はタグ `v0.1.0-jcmi46` に残る）
- 意図: WHERE句で日時に範囲条件（`>=`/`<`）を与え、期間で絞り込むデモ
- 注意: 比較は ISO8601 の文字列比較（辞書順=時間順）。両辺の書式と UTC オフセットをそろえる。
  RM グラフから読み戻したイベント時刻は UTC の `…Z`（`docs/upstream-candidates.md` 21項）。
  フォーム経路のイベント時刻は、保存した時刻
- クエリ:
  ```
  SELECT o/data[at0001]/events[at0002]/time/value AS measured_at
  FROM EHR e CONTAINS COMPOSITION c
       CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.height.v2]
  WHERE o/data[at0001]/events[at0002]/time/value >= "2026-01-01T00:00:00Z"
    AND o/data[at0001]/events[at0002]/time/value < "2026-07-01T00:00:00Z"
  ```
- フォームPOST: 身長の記録を 2026-03-15（期間内）と 2026-09-01（期間外）に 1 件ずつ保存（spec は時刻を進めて投入）
- 期待件数: **1件**（期間内の1件のみ。実測: `docs/reports/m2-log.md` R5）
- **凍結受入条件に算入可能**

## 5. テンプレート横断の傷病名（第 3 幕の横串一貫性、`skoba/anlage#47`）

- 由来: 裁定 2026-10-20（例外報告 R4 への裁定 1）。同じ `openEHR-EHR-EVALUATION.problem_diagnosis.v1` を使う
  ProblemList と jp_referral が **1 本の AQL で同時に引ける**ことの実演
- 状態: **spec 化済み**（`spec/demo/cross_template_query_spec.rb`）
- クエリ:
  ```
  SELECT c/archetype_details/template_id/value AS template_id,
         ev/data[at0001]/items[at0002]/value/value AS diagnosis
  FROM EHR e CONTAINS COMPOSITION c
       CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
  WHERE ev/data[at0001]/items[at0002]/value/value MATCHES {"2型糖尿病", "高血圧症"}
  ```
- 投入: 1〜4 と違いフォーム POST だけでは作れない（jp_referral のフォーム保存は #30 で未対応。ICD-11 コード付きの傷病名もフォーム経路では作れない——ProblemList の at0002 は coded_free で DV_TEXT 保存、WP5／`$lookup`〔12 月〕の既知制限、`docs/backlog.md` 13）。
  `rake demo:reset` の初期状態（`Demo::SampleCompositions`）を使い、壇上の「1 件足す」はフォーム POST
- 期待件数: 初期状態で **7 件**。初期状態は `docs/design/sample-data-plan.md` 3 節の 65 件（2026-11-25、R-20261125-9）。
  - ProblemList「2型糖尿病」2 件（DEMO-01 の ICD-11 5A11 付き、DEMO-05 のコードなし）
  - ProblemList「高血圧症」4 件（確定 2、疑い 1、推定 1）
  - jp_referral「2型糖尿病」1 件（5A11 付き）
  - 糖尿病性腎症は完全一致に当たらない
  - フォームから「2型糖尿病」を 1 件足すと **8 件**
- 出所の並記は template_id（`c/archetype_details/template_id/value`）。openehr 2.6.1・openehr-rails 0.11.0 で届くようになり、
  Composition 名（`c/name/value`）から切り替えた（2026-11-26、`skoba/anlage#177`。`docs/upstream-candidates.md` 25 項）
- **質疑応答用 1 行**: 「紹介先医療機関で引く」（`items[openEHR-EHR-CLUSTER.organisation.v1, '紹介先医療機関']`）は、
  openehr 2.5.0（[openehr-ruby#60](https://github.com/skoba/openehr-ruby/issues/60)）で引けるようになった
  （`spec/integration/jp_referral_aql_spec.rb` の構造骨格。2026-11-24）。このクエリをその形に変えるのは、
  jp_referral のフォーム保存（M2）のあと

---

全4クエリとも供給済み・spec化完了（5 は 2026-10-20 追加、初期状態依存）。`bundle exec rspec spec/demo/`がgreenであることが
`docs/design/demo-queries-plan.md` 5節の凍結受入条件。
