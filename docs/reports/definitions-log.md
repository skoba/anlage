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
- 手元の全 suite: 930 examples, 0 failures, 2 pending

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
- 手元の全 suite（D-2 の上）: 938 examples, 0 failures, 2 pending

## R4（2026-11-28）競合の印の regression pin（`skoba/anlage#263`。R-20261128-1 の「小さいこと」）

- R3 の作業中に、終わっていないマージをコミットして（`5ccf342`）、この進行記録に競合の印が残った。`7518ca4` で消した
- `spec/docs/conflict_markers_spec.rb`: `git grep -nIE '^(<<<<<<<|>>>>>>>)( |$)'` の結果が空であること。
  `=======` は Markdown の見出しの下線と区別できないので見ない（自己承認: 裁定の文言も `<<<<<<<`・`>>>>>>>` の 2 つ）
- Red: `5ccf342` を detached の worktree に出して、同じ spec を走らせた（1 example, 1 failure）

  ```
  競合の印が残っている:
  docs/reports/definitions-log.md:73:<<<<<<< HEAD
  docs/reports/definitions-log.md:96:>>>>>>> feat/259-definitions-context
  ```

  Red に使った worktree は、spec の写しを除いてから外した（`5ccf342` は origin/main の祖先）
- Green: main（`1c25de1`）の上で `bundle exec rspec spec/docs/` → 4 examples, 0 failures

## R5（2026-11-28）ゲート報告: D-3・D-4 の計画（`skoba/anlage#265`。R-20261128-1）

種別: (a) ゲート報告。計画書: `docs/design/definition-registration-plan.md`。実装は回答のあと（migration があるので、必ず止まる 2）。

### 実測（計画の 0 節）

- 患者の画面は、U1 の規則（`app/lib/charts/rules.rb`）で、登録済みのテンプレート全体から部品を決める。定義を読む道は無い
- `Definitions::Linter.call(dir, templates: Template.active)`（`app/lib/definitions/linter.rb:16`）はディレクトリを読む。表から読むには、読み元を分ける
- テンプレートを消す道は、画面と API に無い（`config/routes.rb`）。`demo:reset` が全部を消す（`lib/tasks/demo.rake:24-27`）
- 帳票の保存のあとは、記録の画面に移る（`app/controllers/compositions_controller.rb:82`）
- 認証は無い。任意の Basic 認証だけ（`config/application.rb:35`）

### 決めてほしい点（推す案）

| # | 問い | 推す案 | 捨てた案 |
|---|---|---|---|
| 1 | 表の単位 | 1 行 = 1 つの組の 1 つの版（`definition_bundles`。YAML の文字をそのまま `files` に持つ）。検査の単位（D2・D5・D6）と合い、画面ごとの版が混ざらない | 画面・ロジックを別の行にする |
| 2 | 動かす組の選び方 | 環境変数 `ANLAGE_DEFINITION_BUNDLE=<bundle_id>`。その組の active の版。組の中の版の入れ替えは、再起動なし | 「動かす組」を表に持ち、rake で切り替える |
| 3 | 組が無い・通らないとき | 500 にせず、組み込みの定義（いまの画面）と、理由の文（D コード、場所、候補）を画面の上に出す。検査し直しは、組の行とテンプレートの checksum を鍵にして覚える | エラーの画面にする |
| 4 | 組み込みの定義 | `config/definitions/builtin/`。`from` の無い部品は、U1 の規則で全体から引く（D-1 の書式に意味を足す）。いまの画面と同じ並びと中身を spec で pin する | 組み込みの定義を、初期データのテンプレートを名指しで書く（別のテンプレートを登録すると、画面に出なくなる） |
| 5 | 登録の入口 | 書き込み（登録・動かす・戻す）は rake だけ。画面 `/definitions` は読むだけ（一覧、検査、図、差分、試しに表示のリンク）。認証が無いので、画面から全員の画面を変えられる道を作らない | テンプレートと同じく、画面から登録する。注意書きだけで足りるとする |
| 6 | `demo:reset` | 定義の組も消す（初期データのテンプレートしか残らず、参照が切れるため） | 定義の組は残す |
| 7 | 保存のあとの `then` | 帳票の URL にボタンの印（組の行の id とボタンの id）を付け、保存のあと、サーバが組から先を引き直す。先を URL に書かない | 先の画面を URL に書く |

### 段（回答のあと。計画の 8 節）

D-3a 表とモデル → D-3b rake → D-4a 組み込みの定義 → D-4b 動かす組で出す → D-4c `?preview` と `then` → D-4d 読むだけの画面。
gem は足さない。migration は 1 つ。範囲の外にしたもの（画面からの書き込み、取り込みの前の警告）は `docs/ideas-2027.md` に書いた。

## R6（2026-11-28）D-3a: 定義の組の表とモデル（`skoba/anlage#277`。R-20261128-7）

計画: `docs/design/definition-registration-plan.md` 1 節・1.1 節・5 節（R-20261128-7 で承認）。migration は計画の表のとおり（R-20261128-7「進め方」: このとおりなら CI が green のとき、セッションがマージしてよい）。

- サイクル 1（読み元）: Red `spec/lib/definitions/linter_files_spec.rb` → `NameError: uninitialized constant Definitions::Files`（3 examples, 3 failures）。
  Green: `Definitions::Files.read(dir)`（目録と screens・logic の YAML を、path の順の対応表に）と `Definitions::Linter.check(files)`。`Linter.call(dir)` はその 2 つの組み合わせ。
  1 回目は並びが glob ごとで期待と違った（1 failure）ので、全体を path の順にした（checksum が読む順によらない）。D-1・D-2・D-5 の spec を含めて 48 examples, 0 failures
  - 目録（bundle.yml）が無いときは、例外（`Errno::ENOENT`）ではなく D1 の問題にした（表の組では、ファイルが無いことがあり得る。自己承認）
- サイクル 2（表とモデル）: Red `spec/models/definition_bundle_spec.rb` → `uninitialized constant DefinitionBundle`。
  Green: migration `20261128000001_create_definition_bundles`（計画 1 節のカラム。`(bundle_id, version)` 一意、active は組ごとに 1 つの部分索引 `WHERE status = 'active'`）と
  `DefinitionBundle.register`・`#activate!` → 7 examples, 0 failures
  - 登録: エラーがあれば足さない（D8 の案は `lint_report` に残して足す）。同じ組・版で中身が違えば断る。同じ checksum は「登録済み」
  - 動かす: 直前に、いまのテンプレートで検査し直す。通らなければ `DefinitionBundle::LintFailed`
  - checksum は `files` を path の順に並べた JSON の SHA-256
- サイクル 3（`demo:reset`、回答 6）: Red `spec/tasks/demo_reset_spec.rb` の「登録した定義の組も消す」→ `expected: 0, got: 1`。
  Green: `DefinitionBundle.delete_all`（トランザクションの中）。タスクの説明と README（英・日）に書いた → 10 examples, 0 failures
- rake（register・activate・restore・list）は D-3b

## R7（2026-11-28）D-3b: 定義の組の rake（`skoba/anlage#279`。R-20261128-7 の回答 5 と「足すこと」）

- サイクル 1（戻す）: Red `spec/models/definition_bundle_spec.rb` の `.restore!` 3 例 → `undefined method 'restore!' for class DefinitionBundle`。
  Green: 前の版の `files` を写し、`bundle.yml` の `version:` の 1 行だけを、最新の版のパッチを 1 つ上げた版に替える（`Template.next_version`）。
  替えたあとの組を検査し、通れば新しい行（`restored_from` に元の版）として足して動かす。通らなければ `LintFailed`（足さない）→ 10 examples, 0 failures
  - 「1 行だけ」は spec で、行数が同じで、違う行が `version: 0.1.1` の 1 行だけであることを見た
- サイクル 2（rake）: Red `spec/tasks/definitions_registry_spec.rb` → `Don't know how to build task 'definitions:register'`。
  Green: `definitions:register DIR=`（下書き。エラーは文で出して終了コード 1、同じ版で別の中身も 1、同じ中身は 0）、`definitions:activate BUNDLE= VERSION=`、
  `definitions:restore BUNDLE= VERSION=`、`definitions:list` → 13 examples, 0 failures（既存の `definitions:lint` などの spec を含む）
  - `registered_by` は `rake（<環境の利用者名>）`（`Etc.getlogin`、無ければ `USER`）。運用者の名前で、患者の記録や計測には使わない（10 節）
- Refactor（緑のまま）: `DefinitionBundle::Registration` に `status`（`:registered`・`:invalid`・`:exists`・`:conflict`）を持たせ、rake は status で分ける（24 examples, 0 failures）

## R8（2026-11-28）D-4a: `from: { auto: true }` と組み込みの定義（`skoba/anlage#281`。R-20261128-7 の回答 4）

- サイクル 1（書式）: Red `spec/lib/definitions/auto_from_spec.rb`（6 例）。D-3a の前の main では `Linter.check` が無いので 6 failures、
  D-3a のブランチを取り込んでから 5 failures（記録を引かない部品の例は、はじめから通る）。
  Green: `Definitions::Schema` の `FROM` に `auto`（`enum(true)`）。対の規則: `auto` と一緒に書けるのは `rm_type` だけ。
  `SECTION` の対の規則: 記録を引く部品（`RECORD_COMPONENTS` = problem_list・time_series・lab_table・records・table）で `from` が無いと D1、文に `from: { auto: true }` の書き方。
  `problem_list` の D4（`from.archetype` が要る）は、`auto` のときは出さない
  - 1 回目の Green で 3 failures: D1 を通らない画面は読まれず、その画面への遷移が D5 になる（検査器のこれまでの振る舞い）。spec は D1 だけを見る形にした
  - `auto` に `rm_type` を許した理由（自己承認）: 組み込みの定義で「依頼と紹介状」（U1 の R2、INSTRUCTION）と「記録の一覧」を、同じ `records` で分けるため
  - `rake definitions:context` の部品の説明と、`from_rule`（材料の JSON の新しいキー）。JSON のキーの pin（`spec/tasks/definitions_spec.rb`）を合わせた
- サイクル 2（組み込みの定義）: Red `spec/lib/definitions/builtin_spec.rb` → `NameError`（`Definitions::Builtin`）、`spec/requests/patient_chart_spec.rb` の並びの例 → `got: []`。
  Green: `config/definitions/builtin/`（部品はどれも `from: { auto: true }`）、`Definitions::Builtin`、`Definitions::Section`、`patients/sections/` に部品ごとの中身を分けた
  （もとの `patients/_chart` と、`patients/show` の「カルテ記録」から、そのまま移した。各 `<section>` に `data-definition-section`）。`patients/_chart` は部品の並びを回すだけになった（ファイルは消していない）
  - 1 回目は `Data.define` の `new` を上書きして `NoMethodError`。`Section.from(data)` にした
  - 書いた spec に、確かめていないメソッド（`Demo::SampleCompositions.commit_referral_for_spec!`）を呼ぶ行を入れていた。実在しないので消した（DEMO-01 には紹介状が無く、orders は出ない）
  - `spec/requests`・`spec/views`・患者とデモの system spec: 230 examples, 0 failures（全体は CI。R-20261128-10 のメモリの決まりに合わせた）
- 例の組（`docs/definitions/example/screens/patient_chart.yml`）に `from: { auto: true }` の部品を 1 つ足した
