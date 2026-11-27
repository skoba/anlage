# 定義の層の進行記録

計画: `docs/design/definition-layer-plan.md`（R-20261127-13・16・21）。

## R1（2026-11-27）D-1: 定義の検査器と `rake definitions:lint`（`skoba/anlage#257`。R-20261127-21 の回答 5）

### 自己承認した判断

裁定の範囲（D-1 は実装へ。migration も gem も無い範囲）の中で、計画書が例だけを書いていた点を、次のように決めた。

| 判断 | 採った案 | 捨てた案 | 根拠 |
|---|---|---|---|
| 組の置き方 | 1 つの組 = 1 つのディレクトリ。`bundle.yml`（目録）、`screens/<id>.yml`、`logic/<id>.yml`。ファイル名の id と、中の `screen:`・`logic:` が一致すること | 1 つの大きな YAML | 計画書 1 節（ファイルは 4 種類と目録）。差分と AI の書き直しが 1 ファイルずつで済む |
| 流れ（`flows/`） | D-1 では読まない（目録の `flows:` は書いてよいが検査しない） | D-1 で流れの書式も検査する | D9 は D-7 の段（計画書 5 節）。D-7 は実装の前にゲート |
| YAML の読み方 | `YAML.safe_load(text, permitted_classes: [], aliases: false)`。1 ファイル 64 KiB まで | `YAML.load_file` | 計画書 9 節（別名と任意のクラスを許さない、大きさの上限）。64 KiB は、いまの `config/form_behaviors.yml`（約 1.5 KiB）の 40 倍で、手で書く定義には足りる |
| D8（出どころとレビュー者が無い） | エラーではなく「案」（severity: draft）。終了コードは 0 | エラーにする | 計画書 2.2 の D8「無ければ『案』。保存には効かない」。案として試せる（2.6） |
| 部品の名前 | `problem_list`・`time_series`・`lab_table`・`records`・`form`・`table`・`buttons` | U1 の計画書 2 節の 5 つだけ | U1 で実装した部品（`Charts::Rules` の `:problem_list`・`:lab_table`）を定義でも書けるように。`orders` は `records`（`from: { rm_type: INSTRUCTION }`）で書く |
| D7 の式の検査 | `Opt::Formula.evaluate` に、入力の名前すべてを 1.0 にして評価する。文法の誤りは `Opt::Formula::Error`、入力に無い識別子は `KeyError` | 別の構文解析器を書く | 評価器が正（同じ文法を 2 つ持たない） |

### 書式（D1 の検査器が持つ）

```yaml
# bundle.yml
bundle: clinic_diabetes        # 必須。組の id
version: 0.1.0                 # 必須
title: 糖尿病の外来            # 必須
templates: [ { template_id: LabResultReport } ]   # 任意。登録済みのテンプレート（D3）
screens: [ patient_chart ]     # 任意。screens/<id>.yml
logic: [ bmi_rules ]           # 任意。logic/<id>.yml
flows: [ outpatient_visit ]    # 任意。D-1 では検査しない
start: { screen: patient_chart }   # screens があれば必須（D6 の起点）
```

画面（`screens/<id>.yml`）: `screen`・`version`・`sections` が必須、`title`・`applies_to`（`patient`）が任意。
section は `id`・`component` が必須。`from`（`template`・`archetype`・`field`・`fields`・`rm_type`）、`columns`、`series_key`、`only`、`chart`（`line`）、
`items`（`buttons` だけ。`id`・`label`・`open`〔`form` か `screen`、任意で `then`〔`screen` か `record: saved`〕〕）。

ロジック（`logic/<id>.yml`）: `logic`・`version`・`template`・`rules` が必須、`source`・`reviewed_by` が任意（無ければ D8 の案）。
rule は `id`・`target` が必須。`inputs`、`formula` か `cases`（どちらか 1 つ）、`round`（整数）、`on`（`input`・`save`）、`editable`（真偽）。
cases の要素は `when` と `value`、または `else`。

### 進行

- サイクル 1（読み方）: Red `spec/lib/definitions/loader_spec.rb` → `NameError: uninitialized constant Definitions`（No examples found）。
  Green: `Definitions::Loader`（`YAML.safe_load`、`aliases: false`、`permitted_classes: []`、64 KiB）と `Definitions::Problem`。7 examples, 0 failures
