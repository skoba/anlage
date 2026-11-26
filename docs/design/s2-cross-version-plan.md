# アーキタイプの版をまたいで引く（クエリビルダー）

裁定 ID: R-20261125-10。Issue: `skoba/anlage#154`。状態: 計画を書いて、そのまま実装に進む。版の対応の行は、候補を出したところでゲート報告（レビューは人間）。

- 基準点: anlage main `60a35ae`（openehr 2.5.0、openehr-rails 0.9.0）
- 関連: クエリビルダー（`docs/design/s2-query-builder-plan.md`）、別名表（`docs/design/s3-search-plan.md` 3.1。持ち方の考えを同じにする）

## 1. ねらい

アーキタイプは semver を採っている。小さな改訂（同じ v1 のまま）は ID が変わらないので、同じ問い合わせで引ける。
大きな改訂（v1 → v2）は ID が変わり、互換性を崩してよいので、項目ごとに「同じものか」の確認が要る。
確認済みの対応があれば、版が変わったあとも、過去のデータごと 1 回の操作で引けるようにする。

## 2. いまの状態（実測）

demo_initial のテンプレートのうち、血圧は 2 つの版にある。

| テンプレート | アーキタイプ | 項目 | パス（ENTRY から下） | 型 | 単位 | 値の範囲 |
|---|---|---|---|---|---|---|
| CardiologyEncounter | blood_pressure.v2 | at0004「収縮期」 | `data[at0001]/events[at0006]/data[at0003]/items[at0004]/value` | DV_QUANTITY | mm[Hg] | 0 以上 1000 未満 |
| CardiologyEncounter | blood_pressure.v2 | at0005「拡張期」 | `…/items[at0005]/value` | DV_QUANTITY | mm[Hg] | 0 以上 1000 未満 |
| patient_blood_pressure.v1 | blood_pressure.v1 | at0004「Systolic」 | `data[at0001]/events[at0006]/data[at0003]/items[at0004]/value` | DV_QUANTITY | mm[Hg] | 0 以上 1000 未満 |
| patient_blood_pressure.v1 | blood_pressure.v1 | at0005「Diastolic」 | `…/items[at0005]/value` | DV_QUANTITY | mm[Hg] | 0 以上 1000 未満 |

- 収縮期・拡張期は、at-code、パス、型、単位、値の範囲が v1 と v2 で同じ（カードの `constraints.value` を比べた）
- いまのクエリビルダーは、1 つのクエリで ENTRY のアーキタイプを 1 つしか使えない（判断 G2）。v2 のカードを選ぶと、v1 の記録は出ない

**1 本の AQL で 2 つの版を引けるか**（リポジトリの外の一時の spec で、リンタと `OpenehrRails::Aql::Executor` に通した。v1 の記録を 1 件足した上で）

| 形 | 結果 |
|---|---|
| `CONTAINS OBSERVATION o[…v1]`、`CONTAINS OBSERVATION o[…v2]` を別々の AQL で | どちらも実行でき、それぞれの版の行が返る |
| `CONTAINS (OBSERVATION o[…v1] OR OBSERVATION o2[…v2])` | `OpenEHR::AQL::SemanticError: unbound variable: "o"`（片方の変数が束縛されない行で落ちる） |
| 述語なしの `OBSERVATION o` と `WHERE o/archetype_node_id MATCHES {…}` | `UnsupportedFeature: unsupported path attribute "archetype_node_id"` |

→ **版ごとに別の AQL を組み、結果をアプリの側でまとめる**。CONTAINS の OR は、いまの版のエンジンでは使えない。

## 3. 版の対応

### 3.1 候補（自動で挙げる）

`QueryBuilder::VersionCandidates`: active のカードから、次がすべて一致する項目の組を挙げる。

- アーキタイプの ID から版（末尾の `.v<数字>`）を除いたもの
- at-code
- ENTRY から下のパス（途中の埋め込みアーキタイプの述語は、版を除いて比べる）
- RM の型

組ごとに、単位・値の範囲・値集合（コードの集合）を比べ、違えば印を付ける。候補は Markdown で出す（`rake query_builder:version_candidates`）。
候補は「同じものかもしれない」までで、**問い合わせには使わない**。

### 3.2 対応の表（人間がレビューした行だけを使う）

`config/version_mappings.yml`（YAML 1 つ。別名表と同じ考え方）

```yaml
- concept: openEHR-EHR-OBSERVATION.blood_pressure   # 版を除いたアーキタイプの ID
  at_code: at0004
  versions: [v1, v2]            # 同じものと確かめた版
  status: active                # active／pending（候補のまま。問い合わせには使わない）
  note: "収縮期。単位 mm[Hg]、値の範囲も同じ"
  source: "…"
  reviewed_by: …
  reviewed_at: …
```

- 読み込み: `QueryBuilder::VersionMappings`。形式の誤りは読み込みで止める。active の行には `reviewed_by`・`reviewed_at` が要る。pending の行は読むが使わない
- 最初の候補は、血圧の収縮期（at0004）と拡張期（at0005）。**レビューが済むまで、表には pending で置く**（この PR では active の行は無い）
- 対応の単位は「項目」。同じアーキタイプのほかの項目に、対応は広がらない

## 4. 「版をまたいで引く」

`QueryBuilder::CrossVersion`（実行は `QueryBuilder::Runner.call(…, across_versions: true)`）

1. 選ばれたカード（表示する項目と条件）のすべてに、active の対応の行があることを確かめる。
   1 つでも無ければ組まない（`InvalidSelection`。「版の対応が無い項目: …」）。**ID が似ているだけの項目を、まとめて引かない**
2. 引く版は、選ばれたカードすべての対応に共通で、かつ索引（active のカード）にその版のカードがあるもの
3. 版ごとに、カードをその版のカードに置き換えて、いまのビルダーで AQL を組む（条件の値は同じ）。リンタは AQL ごとに通す
4. どれかの AQL にリンタの error があれば、どれも実行しない。なければ版ごとに実行し、行をつなぐ（版の順）
5. 結果の先頭に、行が来たアーキタイプの ID（版つき）の列を足す

- 条件の種類（数値、値集合、日付、文字列、未記入を含む、範囲の外、どちらかを満たす）は、そのまま使える（AQL ごとに同じ条件を組む）
- 並べ替えと件数の上限は、いまのビルダーに無いので、ここでも無い
- 単位が版で違う項目は、対応の行を active にしない（値の変換はしない。範囲外）

## 5. 画面

- 「表示する項目」の下に、チェック「版をまたいで引く」（`across_versions`）。状態は URL だけ（G4 のまま）
- AQL の欄は、版ごとに見出し（アーキタイプの ID）を付けて並べる。検査の指摘も版ごと
- 結果の表の先頭の列の見出しは「アーキタイプの版」
- 文言は `docs/demo/ui-vocabulary.md` に同じコミットで足す

## 6. テスト TODO

候補: 1. 血圧の v1 と v2 の at0004・at0005 が候補に挙がり、印は付かない 2. 単位か値の範囲が違う組には印が付く 3. at-code かパスか型が違えば候補にしない

表: 4. 読み込みと検査（active にはレビューの記録が要る） 5. pending の行は使わない 6. リポジトリの表は、血圧の 2 行が pending

またいで引く: 7. 版ごとの AQL（v1 と v2 で、述語の版だけが違う） 8. v1 と v2 の記録が 1 つの結果にまとまり、先頭の列が版 9. 条件（収縮期 >= 140、どちらかを満たす）が両方の版に効く
10. 対応の無い項目を含む選択は組まない 11. 索引に片方の版しか無ければ、その版だけを引く 12. pending の対応では組まない

画面: 13. request spec（チェック、版ごとの AQL、列の見出し） 14. 実ブラウザの system spec に 1 例

## 7. 守ること

- 対応の無い項目を、ID が似ているからといってまとめて引かない（4 の 1）
- 意味と構造（パス、型、単位、値の範囲）は OPT から取ったカードのものを使う。対応の表が供給するのは「この版とこの版の、この項目は同じ」だけ（LLM 分業原理と同じ線引き）
- at-code・アーキタイプの ID は実物だけ

## 8. 範囲外

at-code やパスが版で変わった項目の対応、単位の変換、3 つ以上の ENTRY をまたぐ結合、評価の問い（サンプルデータが main に入ったあと、R-20261125-6 の問いの案と一緒に出す）。

## 9. ゲートで問うこと: 版の対応の行のレビュー（2026-11-25）

`rake query_builder:version_candidates`（demo_initial の 5 テンプレート）が挙げた候補は 2 件。

| アーキタイプ（版を除く） | 項目 | 版 | ラベル | 型 | 単位 | 値の範囲 | 違い |
|---|---|---|---|---|---|---|---|
| openEHR-EHR-OBSERVATION.blood_pressure | at0004 | v1、v2 | v1: Systolic／v2: 収縮期 | DV_QUANTITY | mm[Hg] | 0 以上 1000 未満 | なし |
| openEHR-EHR-OBSERVATION.blood_pressure | at0005 | v1、v2 | v1: Diastolic／v2: 拡張期 | DV_QUANTITY | mm[Hg] | 0 以上 1000 未満 | なし |

- 2 行とも、`config/version_mappings.yml` に **pending** で置いてある。画面で「版をまたいで引く」をチェックしても、いまは
  「版の対応が無い項目がある」と出て実行されない（仕組みは、spec の中で active の行を渡して確かめてある）

問うこと:

1. **この 2 行を active にしてよいか**（v1 と v2 の収縮期・拡張期は同じもの、と確かめる）。よければ、`status: active` と
   `reviewed_by`・`reviewed_at` を書く。この 2 行を active にすると、デモで v1 と v2 の血圧を 1 つの表に引ける
2. セッションが比べたのは、カードにある情報（at-code、パス、型、単位、値の範囲）だけ。**アーキタイプの改訂の内容**
   （v1 → v2 で、測定の定義・プロトコルの項目・状態の項目がどう変わったか）は見ていない。対応を認めるのに、それが要るか
3. ラベルは、v1 が英語（Systolic、Diastolic）、v2 が日本語。まとめた結果の列の見出しは、選んだカードのラベルを使っている

### 9.1 回答（2026-11-26。根拠は R-20261125-11）

- 2 行（収縮期 at0004、拡張期 at0005）を active にした。`reviewed_by: Kobayashi, Shinji`、`reviewed_at: 2026-11-25`。
  note に、確かめた範囲（at-code、パス、型、単位、値の範囲が同じ。アーキタイプの改訂の内容は、セッションは比べていない）を書いた
- まとめた結果の列の見出しは、いまのまま（選んだカードのラベル）
- 2 節の「1 本の AQL で引けない」2 件は `docs/upstream-candidates.md` 29・30 項。上流が直っても、版ごとに別の AQL を組む作りは変えない
