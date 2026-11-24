# 帳票に入力欄の無い RM の属性: 進行ログ

設計: `docs/design/rm-attributes-without-inputs.md`（承認済み、R-20261124-14）。作業列: R-20261124-10。
5 節の 1（`#86`）と 2（`#87`）、設計書そのものの記録は `docs/reports/m2-log.md` R3・R4・R6 にある。
このファイルは 5 節の 3 から（`m2-log.md` の末尾は、人間のマージ待ちの PR #105 が触っていて競合するので、分けた）。

## R1 5 節の 3（`skoba/anlage#109`）: ノードの名前をテンプレートの用語から取る（2026-11-24）

ブランチ `feat/109-node-names`。基準点は main `5ad061b`。

### ゲート報告: COMPOSITION の名前（変えていない。人間の判断を待つ）

設計書 3 節の表は、COMPOSITION の name も「ルートの at0000 の text」にするとしていた。実測すると、そうすると壇上の表示が悪くなる:

| OPT | いまの name（concept） | ルートの at0000 の text |
|---|---|---|
| CardiologyEncounter | CardiologyEncounter | 循環器内科外来診察 |
| LabResultReport | LabResultReport | Report |
| ProblemList | ProblemList | ProblemList |
| bmi_calculation | bmi_calculation | Report |
| jp_referral | jp_referral | jp_referral |
| patient_blood_pressure | COLNEC Patient Blood Pressure.v0 | Encounter |

- 6 つのうち 3 つで、at0000 がアーキタイプの既定の名前（`Report`・`Encounter`）のまま
- デモクエリ 2・3・5 と実ブラウザの spec は、`c/name/value` を出所の表示に使っている
  （`spec/demo/aql_queries_spec.rb:55`・`:87`、`spec/demo/cross_template_query_spec.rb:14`、`spec/system/demo_problem_list_spec.rb:33`）。
  変えると、たとえば `bmi_calculation` が `Report` になり、2 つのテンプレートが同じ名前になる
- 選べる形: (a) concept のまま（いま。推奨）、(b) at0000 の text、(c) at0000 が既定の名前でなければ text、そうでなければ concept
- 推奨は (a)。出所は template_id で引くのが本来で（上流候補 25 項が直れば `c/archetype_details/template_id/value`）、
  name は人が付けたテンプレートの名前のままにしておくほうが、記録を見分けやすい
- この判断を待たずに、ほかのノードは進めた。spec に「COMPOSITION の name は変えない」を pin した

### 自己承認した判断

1. **名前は登録時に `web_template` の entry に入れる**（`label` と `node_labels`）。builder は読むだけ。
   キーが無い登録済みの web_template では、これまでの値（concept、`history`、`event`）に落ちる。移行は要らない
2. **`node_labels` に入れるのは、field の path に現れる途中のノード（at-code を持つもの）だけ**。
   アーキタイプの全 at-code を入れると web_template が膨らむ
3. **用語が無いノードは、これまでの値のまま**（例: CardiologyEncounter の blood_pressure は at0002 の用語を持たない）
4. **用語の出どころは、既にある `instance_terms`**（`Template.serialize_entry` に渡っている、そのルートの term_definitions）。
   PR #105（`Opt::RootTerms`）のマージを待たずに済む。#105 とは `template.rb` の別の行を触る
5. **name を使う箇所を洗った**（設計書 5 節の注）: app は AQL を組まない。spec と文書で name を使うのは、
   `c/name/value`（COMPOSITION。変えていない）と、CLUSTER の name 述語（`'紹介先医療機関'`。CLUSTER の name は `#38` で既にテンプレート上の名前）だけ。
   ENTRY・HISTORY・EVENT・ITEM_TREE の name を引く箇所は無い（grep）。引く側のレーンのパスカード検索は、保存した記録を読まない

### 実測（fixture の OPT の用語）

- LabResultReport の検体検査結果: at0000「検体検査結果」、at0001「Event Series」、at0002「任意のイベント」、at0003「Tree」
  （`spec/fixtures/opt/LabResultReport.opt:1046-1049` ほか）
- ProblemList のプロブレム・診断: at0000「プロブレム・診断」、at0001「structure」
- jp_referral: 「傷病名」「既往歴及び家族歴」（同じ problem_diagnosis でも、テンプレートごとに名前が違う）

### Red（実装の前、5 例 3 失敗。「COMPOSITION は変えない」「キーが無ければこれまでの値」の 2 例は実装の前から緑）

```
1) Opt::CompositionBuilder#109 ノードの名前 OBSERVATION: ENTRY・HISTORY・EVENT・ITEM_TREE の name が、テンプレート上の名前になる（LabResultReport）
     expected: "検体検査結果"
          got: "laboratory_test_result"
2) … EVALUATION: ENTRY の name がテンプレート上の名前になる（ProblemList）
     expected: "プロブレム・診断"
          got: "problem_diagnosis"
3) … 同じアーキタイプの別のルートは、それぞれの名前を持つ（jp_referral の傷病名）
     expected: ["傷病名", "既往歴及び家族歴"]
          got: ["problem_diagnosis", "story"]
```

### Green

- 開発機の全 suite: 291 例 0 失敗、2 pending。`spec/demo/` と FHIR の spec は期待値を変えずに緑。rubocop 違反なし
