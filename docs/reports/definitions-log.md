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
| D7 の式の検査 | 式の識別子を `Opt::Formula::TOKEN` で拾い、すべてを 1.0 にして `Opt::Formula.evaluate` で評価する（文法の誤りは `Opt::Formula::Error`）。そのあと、識別子が `inputs` に含まれるかを見る | 別の構文解析器を書く | 評価器が正（同じ文法を 2 つ持たない） |

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
- サイクル 2（D1 書式）: Red `spec/lib/definitions/schema_spec.rb` → `NameError: uninitialized constant Definitions::Schema`（No examples found）。
  Green: `Definitions::Schema`（Ruby の小さな検査器。必須・未知のキー〔候補に使えるキー〕・型・列挙・対の規則）。8 examples, 0 failures
- サイクル 3（D2〜D8、組のディレクトリ）: Red `spec/lib/definitions/linter_spec.rb` → `NameError: uninitialized constant Definitions::Linter`（No examples found）。
  Green: `Definitions::Linter`（目録 → 画面・ロジックの読み込み〔D1 を通らないものはほかの検査をしない〕、D2 id の重なり、D3 参照と候補、D4 部品と型、
  D5 遷移先、D6 到達、D7 対象・入力・式、D8 案）。11 examples, 0 failures。組の fixture は `spec/fixtures/definitions/clinic`（参照は実物の OPT の field と at-code だけ）
- サイクル 4（`rake definitions:lint`）: Red `spec/tasks/definitions_spec.rb` → `RuntimeError: Don't know how to build task 'definitions:lint'`（4 examples, 4 failures）。
  Green: `lib/tasks/definitions.rake`（`DIR=`、`FORMAT=json`、エラーがあれば終了コード 1、案だけなら 0）。4 examples, 0 failures
- 手元の全 suite: 884 examples, 0 failures, 2 pending

## R2（2026-11-27）D-2: `rake definitions:context`（`skoba/anlage#259`。R-20261127-21 の回答 3）

### 自己承認した判断

| 判断 | 採った案 | 捨てた案 | 根拠 |
|---|---|---|---|
| 項目のどのキーを写すか | allowlist: `name`・`label`・`rm_type`・`archetype_id`・`node_id`・`units` | 外すキーを並べる（denylist） | web_template の field には `code_bindings`・`code_list`・`code_labels`・`value_set_uri`・`terminology_id` がある（実測）。新しいキーが足されても漏れない |
| アーキタイプの ID と at-code | 入れる | 入れない | 定義が参照するのはこれ（D3。`columns: [ at0002 ]`）。CKM の公開のモデルの識別子で、用語のコードでも記録でもない。裁定の「項目の名前」（`problem_diagnosis_at0002`）にも含まれている |
| 選択肢の表示（`code_labels`） | 入れない | 入れる | 裁定の「入れてよいもの」に無い。値集合の中身に近い |
| 例 | `docs/definitions/example/`（spec の組の写し。bundle と logic の注釈だけ直した）。例が検査を通ることを spec で確かめる | spec の fixture をそのまま材料にする | 材料が spec の置き場を指すのは不自然。例が古くなったら spec が落ちる |

### 進行

- サイクル 1（材料）: Red `spec/lib/definitions/context_spec.rb` → `NameError: uninitialized constant Definitions::Context`（No examples found）。
  Green: `Definitions::Context`、`Definitions::Schema.to_json_schema`（検査器から書き出す写し）、`docs/definitions/example/`。5 examples, 0 failures。
  防火壁の spec は、初期データ（demo_initial）を入れた状態で、bindings・コード・値集合・記録の値・患者と EHR の ID・OPT が材料に出ないことを見る
- サイクル 2（`rake definitions:context`）: Red `spec/tasks/definitions_spec.rb` → `Don't know how to build task 'definitions:context'`（6 examples, 2 failures）。
  Green: Markdown（既定）と JSON。定義の spec と合わせて 37 examples, 0 failures

## R3（2026-11-27）D-5: 遷移の図（`skoba/anlage#260`。R-20261127-21 の回答 5）

### 自己承認した判断

| 判断 | 採った案 | 捨てた案 | 根拠 |
|---|---|---|---|
| 節 | 画面、帳票（`open.form`）、保存した記録（`then: { record: saved }`） | 画面だけ | 帳票を開いて保存したあとに進む先（`then`）は、帳票の節から出る辺で書くと、どこで入力が起きるかが図で分かる（4 節の計測の鍵と同じ単位） |
| 図を作る条件 | 検査（D1〜D8）でエラーの無い組だけ | エラーがあっても描けるところまで描く | 参照の切れた辺を描かない。`rake definitions:diagram` はエラーを出して終了コード 1 |
| 画面に置く入口 | 作らない（SVG は helper まで） | 定義の組の画面を足す | 組の登録は D-3（migration。ゲート）。登録の前に画面を足すと、ファイルを読む公開の入口が増える |
| 配置 | start から辿った段を左から右、同じ段は上から下。戻る辺は破線 | 配置の計算（交差を減らす） | 計画書 3.1「段の順に左から右へ並べる単純な配置から始める」 |

### 進行

- サイクル 1（図の節と辺、Mermaid）: Red `spec/lib/definitions/diagram_spec.rb` → `NameError: uninitialized constant Definitions::Diagram`（No examples found）。
  Green: `Definitions::Diagram`（`Linter::Report` に、D1 を通った bundle・screens・logics を足した）。4 examples, 0 failures
- サイクル 2（start だけの組、SVG）: Red → `NameError: uninitialized constant DefinitionsHelper`。start の節に辺が無いときにラベルが引けない誤りも、この例で直した。
  Green: `DefinitionsHelper#transition_diagram`（サーバで描く SVG、依存なし）と、`components.css` の図の色（変数）。6 examples, 0 failures
- サイクル 3（`rake definitions:diagram`）: Red `spec/tasks/definitions_spec.rb` → `Don't know how to build task 'definitions:diagram'`（8 examples, 2 failures）。
  Green: Mermaid のテキスト。エラーのある組は検査の結果だけを出して終了コード 1
