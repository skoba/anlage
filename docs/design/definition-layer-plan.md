# 定義の層の計画（画面・遷移・ロジック・業務の流れ・計測）

裁定 ID: R-20261127-13 の「定義の層の計画」（A・B・C・段）と、R-20261127-16 の 2・3。状態: **承認（R-20261127-21）。回答は 6 節、足したことは 9 節**。D-1・D-2・D-5 は実装へ、ほかの段は実装の前にゲート。
基準点: anlage main `79750cd`（openehr 2.6.1、openehr-rails 0.12.0）。出発点は `docs/design/u1-patient-chart-plan.md` 2 節の書式（R-20261127-13 の回答 5）。

ねらい（小林、11/27）: Anlage をもとにした開発は、生成 AI を使って行われることが多くなる。生成 AI が、画面の遷移やロジックを作り込みやすい
仕掛けにする。それをもとに、病院の業務の流れと画面の遷移を設計しやすくする。遷移や入力に時間がかかるところが見えれば、DX も進む。

## 0. 方針（R-20261127-16）

- ロジック（GDL に当たるもの）と業務の流れ（Task Planning に当たるもの）は、**いまは YAML の軽い定義を優先**し、GDL2 や Task Planning が
  普及した時点で乗り換える。乗り換えの条件: 主な実装が採用し、定義を持ち運ぶ相手ができたとき
- GDL2 は openEHR の仕様として正式に採用されている（CDS Release 2.0.1、状態 STABLE）。採らない理由は普及の見込み
- Task Planning は土台にしない（R-20261127-16 の 3）。公式の状態は、PROC Release 1.7.0 で RETIRED、開発版で PAUSED
- 乗り換えのときに変換を書けるように、概念の対応を 8 節に書く。いまは変換も読み込みも作らない

## 1. 定義の種類と「定義の組」（A）

AI が書くのは**定義**で、コードではない。定義は 5 種類。どれも YAML で、版を持ち、実行時に置く（テンプレートと同じ）。

| 種類 | 中身 | いまの形 |
|---|---|---|
| テンプレート | OPT（臨床のモデル） | 取り込みの画面（実装済み） |
| 画面 | 部品の並び（帳票、記録の一覧、表、時系列、ボタン） | U1 の計画書 2 節の案 |
| 遷移 | 画面から画面へ。ボタン（`open`）と、帳票の保存のあと（`then`） | 同上 |
| ロジック | 帳票の振る舞い（対象、入力、式、条件による値、いつ動くか、編集できるか） | `config/form_behaviors.yml`（起動時に読む） |
| 流れ | 役割、段、段ごとの画面（3 節） | 無し |

遷移は、画面の定義の中に書く（別のファイルにしない。R-20261127-21 の回答 1）。ファイルとしては、画面・ロジック・流れ・テンプレート（OPT）の 4 種類と、定義の組の目録。

**定義の組**: 1 つの電子カルテを成す、テンプレート・ロジック・画面・遷移・流れの目録。別の組を置くと、別の電子カルテが立ち上がる。

```yaml
# 定義の組（案）。この目録 1 つと、そこから参照する定義のファイルで 1 つの電子カルテになる
bundle: clinic_diabetes          # 組の id（変わらない）
version: 0.1.0
title: 糖尿病の外来
templates:                        # テンプレートは template_id と版で参照する（OPT は別に取り込む）
  - { template_id: ProblemList, version: ">= 1.0.0" }
  - { template_id: LabResultReport, version: ">= 1.0.0" }
  - { template_id: CardiologyEncounter, version: ">= 1.0.0" }
screens: [ patient_chart, lab_entry ]          # 画面の定義の id
logic:   [ bmi_calculation_rules ]             # ロジックの定義の id
flows:   [ outpatient_visit ]                  # 流れの定義の id
start:   { screen: patient_chart }             # 患者を開いたときの画面
```

- 1 つの Anlage で動かす組は、いまは 1 つ。どの組を動かすかは、運用者の設定で選ぶ（R-20261127-21 の回答 1）
- 利用者と役割は、認証の計画で足す。いまの目録には入れない

### 1.1 変わらない id

画面・部品・ボタン・遷移・ロジックの規則・流れの段に、変わらない id を持たせる（`screen.sections[].id`、`buttons[].id` など）。
差分、検査のエラー、計測（4 節）は、この id を鍵にする。id は組の中で一意で、版をまたいで同じものを指す。

```yaml
screen: patient_chart
version: 1.2.0
sections:
  - id: problems
    component: problem_list
    from: { archetype: openEHR-EHR-EVALUATION.problem_diagnosis.v1 }
  - id: labs
    component: lab_table
    from: { template: LabResultReport }
  - id: actions
    component: buttons
    items:
      - id: enter_lab
        label: 検査結果を入力
        open: { form: LabResultReport, then: { screen: patient_chart } }
```

## 2. 機械が検査できる形（A）

### 2.1 書式の定義（スキーマ）を公開する

- 定義の種類ごとに JSON Schema を 1 つ（`docs/definitions/schema/*.json`）。YAML は JSON Schema で検査できる
- スキーマの検査には gem が要る（例: json_schemer）。**足さない案**: スキーマを Ruby の小さな検査器（キー・型・列挙の検査）で持ち、
  公開用の JSON Schema は検査器から書き出す。推す案は「足さない」（依存の方針。足すならゲート）
- 正は検査器で、書き出した JSON Schema は写し。食い違ったら検査器が正（R-20261127-21 の回答 2）
- 定義の YAML は、安全な読み方だけで読む（`YAML.safe_load`。別名〔alias〕と任意のクラスを許さない）。1 つのファイルの大きさに上限を置く（9 節）

### 2.2 検査（リンタ）の一覧

置けるのは、スキーマと検査器を通った定義だけ。クエリビルダーのリンタ（`QueryBuilder::Linter`）と同じく、登録済みのテンプレート（パスカード）だけを
知識源にする。

| # | 検査 | 例 |
|---|---|---|
| D1 | 書式（スキーマ）に合う | 未知のキー、必須のキーが無い、型が違う |
| D2 | id が組の中で重ならない | 2 つの画面が同じ `id` |
| D3 | 参照するテンプレート・field・archetype・at-code が、登録済みのテンプレートに実在する | `from: { template: LabResultReport, field: … }` |
| D4 | 部品と項目の型が合う | `time_series` に DV_TEXT の field、`problem_list` に problem_diagnosis 以外 |
| D5 | 遷移先の画面・帳票が実在する | `open: { screen: lab_entry }` の画面が無い |
| D6 | どこからもたどり着けない画面が無い | `start` とボタン・`then` から到達しない画面 |
| D7 | ロジックの対象と入力が、帳票の field に実在し、型が合う（式は `Opt::Formula` の文法） | 未知の識別子 |
| D8 | ロジックに出どころとレビュー者がある（無ければ「案」。保存には効かない） | `source:`・`reviewed_by:` が無い |
| D9 | 流れの段の画面・役割が実在する | 段の画面が組に無い |

### 2.3 エラーの文

どの定義の、どこを、どう直すかが分かる形にする（AI が読んで直せる。人間にも読める）。機械が読む形と、人が読む文の両方を出す。

```
screens/patient_chart.yml: sections[id=labs].from.field: "laboratory_test_analyte_at0002" は LabResultReport に無い。
  候補: laboratory_test_analyte_at0001（分析結果）、laboratory_test_analyte_at0024（分析名）  [D3]
```

```json
{ "code": "D3", "definition": "screens/patient_chart.yml", "pointer": "/sections/1/from/field",
  "id": "labs", "message": "…", "candidates": ["laboratory_test_analyte_at0001", "laboratory_test_analyte_at0024"] }
```

### 2.4 AI に渡す材料の入口

AI が定義を書くのに要る材料を、1 つの入口から取れるようにする: 登録済みのテンプレートの項目の一覧（パスカード）、使える部品の一覧と、
部品ごとに受け取るもの、スキーマ、例。

| 案 | 中身 | 良い点 | 弱い点 |
|---|---|---|---|
| **rake（推す）** | `rake definitions:context` が Markdown と JSON を出す（項目、部品、スキーマ、例）。`rake definitions:lint FILE=…` が検査の結果を出す | 依存なし。AI のエージェント（Claude Code、Codex）がそのまま呼べる。CI でも使える | 動いている Anlage の外からは呼べない |
| 読み取りの API | `GET /definitions/context.json`、`POST /definitions/lint` | 動いているサーバーから取れる | 認証が無いあいだは公開の入口が増える（既知の制限 1） |
| MCP の口 | 上と同じものを MCP のツールで | AI の道具として自然 | gem または別のプロセスが要る（ゲート） |

推すのは rake。API と MCP は、認証の計画（別）のあとに比べ直す。

**材料は、外の LLM に送られる前提で作る**（コンテンツ防火壁。R-20261127-21 の回答 3。S4 の「外に送ってよいもの」〔R-20261127-14〕と同じ線）:

| 入れてよい | 入れない |
|---|---|
| テンプレートの項目の名前・見出し・型・単位、部品の一覧、スキーマ、例 | 記録の中身、患者や EHR の ID、パスカードの bindings と用語のコード、用語マスターの文言、外部の値集合の中身、OPT のファイルそのもの |

spec で確かめる: 材料に、bindings と記録の値が出ない（D-2 の Red の見出しに足す）。

### 2.5 試しに表示する・版・差分・戻す

- 置く前に、試しに表示できる: 検査を通った定義を「下書き」として登録し、URL の印（`?preview=<下書きの id>`）を付けたときだけ使う。
  動いている定義は変えない
- 版: テンプレートの版の仕組み（`status` が active と superseded、版の履歴、`Template#supersede!`）にそろえる。定義の版を上げると、前の版は superseded
- 差分: id を鍵にした差分（足した・消した・変えた部品とボタンと遷移）。テンプレートの差分の画面（`/templates/:id/diff`）と同じ形
- 戻す: 前の版を active に戻す（新しい版として足す。履歴は消さない）

### 2.6 ロジックの有効化

ロジックの定義は、**出どころ（`source`）とレビュー者（`reviewed_by`）が書かれたものだけ**を有効にする（別名表、版の対応と同じ扱い）。
レビューの前のロジックは、案として試せる（帳票の即時表示まで）が、保存には効かない（サーバの再計算をしない）。

```yaml
logic: bmi_calculation_rules
version: 1.0.0
template: bmi_calculation
source: 日本肥満学会「肥満症診療ガイドライン」の肥満度分類（BMI 区分、4.0 版の表記）   # config/form_behaviors.yml の注釈の写し。「4.0 版」が何を指すかは、D-6 の前に人間に確かめる
reviewed_by: "<レビューした人>（<日付>）"   # 例の書き方。記録で確かめられないレビュー者は書かない
rules:
  - id: bmi
    target: body_mass_index
    inputs: [height, body_weight]
    formula: "body_weight / (height / 100) ^ 2"
    round: 1
    "on": input
    editable: false
```

### 2.7 LLM 分業原理との関係

- AI が出すのは、**並べ方と対応付け**: どの部品をどこに置くか、どの field をどの部品に渡すか、どの画面からどの画面へ進むか
- 意味・型・値集合・コードは、テンプレート（OPT）から。検査器（D3・D4）が、定義の参照をテンプレートに照らす
- 臨床の式としきい値は、出どころとレビューから（2.6）。AI が書いた式は、レビューまで保存に効かない

### 2.8 手引き（定義の育て方）

生成 AI を使う人のための手引きを 1 つ書く（`docs/definitions/README.md`、日本語と英語）: 定義の種類、組の作り方、`rake definitions:context` で材料を取る、
書く、`rake definitions:lint` で検査する、試しに表示する、版を上げる。例は初期データのテンプレートで。

## 3. 定義から、流れが見える（B）

### 3.1 遷移の図を自動で出す

画面と遷移の定義から、遷移の図（画面が節、ボタンと `then` が辺）を出す。

| 案 | 中身 | 良い点 | 弱い点 |
|---|---|---|---|
| **画面の中に SVG（推す）** | 組の画面に、サーバで描く SVG の図（U1 のグラフと同じく、依存なし）。節を押すとその画面の定義へ | 図と定義が同じ画面で行き来できる。計測（4 節）を重ねられる | 配置の計算を自前で書く（段の順に左から右へ並べる単純な配置から始める） |
| 文書用のテキストの図 | `rake definitions:diagram` が Mermaid のテキストを出す | 文書や PR に貼れる。AI が読める | 画面の中では描けない（Mermaid の JS を足すならゲート） |

推すのは両方（画面の中は SVG、文書用にテキスト。テキストの出力は依存なしで書ける）。

### 3.2 業務の流れの軽い定義

画面の定義の上に、役割、段、段ごとの画面を書く。Task Planning は土台にしない（R-20261127-16 の 3）。

```yaml
flow: outpatient_visit
version: 0.1.0
roles:
  - { id: nurse, label: 看護師 }
  - { id: physician, label: 医師 }
steps:
  - id: vitals
    role: nurse
    screen: vitals_entry            # 血圧・身長・体重の帳票の画面
    next: [ consult ]
  - id: consult
    role: physician
    screen: patient_chart
    next: [ order, done ]           # どちらかに進む（選ぶのは人）
  - id: order
    role: physician
    screen: referral_entry
    next: [ done ]
  - id: done
```

- 流れの定義は、設計の図と計測の鍵に使う。患者ごとの進み具合（いまどの段か）は、いまは持たない（持つなら、別の計画。R-20261127-21）
- 段は画面を 1 つ持つ。`next` は次の段（複数なら人が選ぶ）。条件による分岐は、最初は持たない（必要になったら、ロジックの式で書く）
- 役割は、認証の計画（別）が利用者と役割を決めるまで、表示の見出しだけに使う

### 3.3 往復

図を見て定義を直すと、図と画面が変わる: 定義を直す → 検査 → 下書きで試しに表示（図も下書きの定義から描く）→ 版を上げる。

## 4. 時間のかかるところが見える（C）

### 4.1 測るもの

定義された画面と遷移は、既定で計測する（定義の id を鍵にする）。

| 測るもの | 鍵 |
|---|---|
| 画面ごとの滞在の時間 | 画面の id、定義の版 |
| 帳票を開いてから保存するまでの時間 | 帳票（template_id）、画面の id |
| 検証で戻された回数と項目 | 帳票、field の name（値は入れない） |
| 戻る遷移 | 遷移の元と先の画面の id |
| 途中でやめた帳票 | 帳票、開いた画面の id |

### 4.2 守ること（決まり）

- 記録の中身と、患者を特定できるもの（患者 ID、EHR ID、記録の uid）を、計測に入れない
- 個人の監視にしない。既定は、画面ごと・役割ごとの集計にする
- 計測は Anlage の中にとどめる。外に送らない
- 運用者が、設定で計測を止められる。計測していることと、測るものを、画面か文書で示す（R-20261127-21 の回答 4）
- 画面から送る出来事は、定義にある id だけを受ける。知らない id と自由な文字列は捨てる
- 元の出来事を持つ期間を決める。集計のあとに消すなら、その作りも D-8 のゲートで決める

### 4.3 見せ方

- 遷移の図（3.1）に重ねる: 節に滞在の時間の中央値、辺に通った回数、戻る遷移を別の色
- 定義の版ごとに比べる（直す前とあと）

### 4.4 持ち方

| 案 | 中身 | 良い点 | 弱い点 |
|---|---|---|---|
| Rails に備わった仕組み（`ActiveSupport::Notifications` とログ） | 出来事をログに書き、集計は rake で読む | 表を足さない（migration なし） | 集計が遅い。図に重ねるには毎回ログを読む |
| **表を足す（推す）** | 出来事の表（画面の id、定義の版、種類、時間、役割、時刻だけ）と、日ごとの集計の表 | 図に重ねられる。版ごとの比較が速い | migration が要る（ゲート） |

推すのは表を足す案（実装のときにゲート）。出来事は、画面の表示（サーバ）と、帳票の開閉・保存（Stimulus の controller が送る）から作る。

### 4.5 認証が無いあいだ

利用者と役割は、認証の計画と重なる。認証が無いあいだは、利用者と役割を持たずに測れるもの（画面の滞在、帳票の時間、検証で戻された回数）から始める。
役割ごとの集計は、認証のあと。

## 5. 段（実装の段の案。実装には進まない）

| 段 | 中身 | Red から始める spec の見出し |
|---|---|---|
| D-1 | 定義の検査器（D1〜D8）と `rake definitions:lint`。定義はファイルのまま（登録はまだ） | 「存在しない field を参照する画面の定義は D3 のエラーになり、候補を出す」「どこからもたどり着けない画面は D6」「id の重なりは D2」 |
| D-2 | `rake definitions:context`（AI に渡す材料） | 「材料に、登録済みのテンプレートの field と、部品ごとに受け取る型が出る」 |
| D-3 | 画面の定義の登録・版・差分・下書き（migration。ゲート） | 「下書きの画面の定義は ?preview のときだけ使われ、動いている画面は変わらない」「版を上げると前の版は superseded」 |
| D-4 | 画面の定義で患者の画面を上書きする（U1 の既定の画面 = 組み込みの定義） | 実ブラウザ: 「定義の部品の並びで患者の画面が出る」「帳票の保存のあと、`then` の画面に進む」 |
| D-5 | 遷移の図（SVG とテキスト） | 「画面の定義から、節と辺の数が定義どおりの図が出る」 |
| D-6 | ロジックの定義の登録（`form_behaviors.yml` の置き換え。出どころとレビュー者が無いものは保存に効かない） | 「レビュー者の無いロジックは、保存のときに再計算しない」 |
| D-7 | 流れの定義（役割・段・画面） | 「流れの段の画面が組に無ければ D9」 |
| D-8 | 計測（表。migration。ゲート） | 「計測の出来事に、患者 ID・EHR ID・記録の値が入らない」「画面の滞在の時間が、画面の id と版ごとに集計される」 |

- D-1・D-2・D-5 は migration も依存も要らない。先に進められる
- D-3・D-4 は 1 つの計画にまとめた: `docs/design/definition-registration-plan.md`（R-20261128-1。`skoba/anlage#265`。ゲート報告は `docs/reports/definitions-log.md` R5）
- 範囲の外: 定義の組の配布（パッケージ）、GDL2・Task Planning の読み込みと変換、利用者ごとの画面

## 6. 問い（ゲート）

1. 定義の 5 種類と「定義の組」の目録の形（1 節）でよいか
   - **回答（R-20261127-21）**: よい。遷移は画面の定義の中に書く（ファイルは 4 種類と目録）。動かす組はいまは 1 つで、運用者の設定で選ぶ。利用者と役割は認証の計画で足す（1 節に反映）
2. スキーマの検査は gem を足さず、Ruby の小さな検査器から JSON Schema を書き出す（推す）でよいか
   - **回答**: よい。正は検査器で、JSON Schema は写し（2.1 節に反映）
3. AI に渡す材料の入口は rake（推す）でよいか
   - **回答**: よい。材料は外の LLM に送られる前提で作る（コンテンツ防火壁。2.4 節に反映。spec で確かめる）
4. 計測は表を足す（推す。実装のときにゲート）でよいか
   - **回答**: よい（実装の前にゲート。変わらない）。止める設定、示すこと、定義の id だけを受けること、持つ期間を守ることに足した（4.2 節に反映）
5. 段の順（D-1・D-2・D-5 を先に。migration の要る D-3・D-8 はゲート）でよいか
   - **回答**: よい。D-1・D-2・D-5 は実装に進む（migration も gem も無い範囲。CI が green ならセッションがマージ）。順番は U1 と版上げ（R-20261127-20・30）が先。
     D-3・D-4・D-6・D-7・D-8 は、それぞれ実装の前にゲート報告

## 7. 参考: いまある仕組みとの関係

- 別名表（`config/search_aliases.yml`）、版の対応（`config/version_mappings.yml`）: 人間がレビューした行だけを使う → 2.6 のロジックの有効化と同じ考え方
- クエリビルダーのリンタ（`QueryBuilder::Linter`）: 登録済みのテンプレートを知識源にした検査と、直し方の分かるエラー → 2.2・2.3
- テンプレートの版と差分（#98・#100）→ 2.5

## 8. 軽い定義と、GDL2・Task Planning の対応（R-20261127-16 の 2）

公式の仕様を読んで書いた（2026-11-27。GDL2 は CDS Release 2.0.1 の
https://specifications.openehr.org/releases/CDS/latest/GDL2.html 、Task Planning は PROC Release 1.7.0 の
https://specifications.openehr.org/releases/PROC/latest/task_planning.html と開発版）。対応が付かないものは「対応なし」と書き、推測で埋めない。
ねらいは、あとで乗り換えるときに、変換が書けること。いまは変換も読み込みも作らない。

### 8.1 ロジックの定義 ↔ GDL2

| 軽い定義（`form_behaviors.yml` の規則） | GDL2 | 備考 |
|---|---|---|
| ロジックの定義 1 つ（template に結び付く規則の集まり） | `GUIDELINE`（`id`、`concept`、`definition`、`terminology`。5.2.2.1） | GDL2 の id は `concept_name.vN` |
| `template`（どのテンプレートの帳票か） | `DATA_BINDING` の `model_id`・`template_id`（5.2.2.4） | GDL2 は入力と出力で別の DATA_BINDING を持てる |
| `inputs`（入力の field の name） | `DATA_BINDING`（`type` = INPUT）の `bindings`（gt-code → `ELEMENT` の `path`。5.2.2.4・5.2.2.5） | 軽い定義は field の name で書く。変換では name → path（web_template の field の path）と gt-code の採番が要る |
| `target`（書き込む field） | `DATA_BINDING`（`type` = OUTPUT）の `ELEMENT` | 同上 |
| `formula`（式） | `RULE` の `then` の `ASSIGNMENT`（`variable = expression`。5.3.2.19）。演算子は `OPERATOR_KIND`（四則・累乗・比較・論理。5.3.2.5）、関数は `FUNCTION_CALL`（5.3.2.6） | `round` は GDL2 の関数に対応するか、仕様の関数の一覧で確かめてから変換を書く（ここでは未確認） |
| `cases`（`when` → `value`、`else`） | `RULE`（`when: List<ASSERTION>` と `then: List<ASSIGNMENT>`、`priority`。5.2.2.3）を、`when` ごとに 1 つ。`else` は条件の否定の RULE か、低い `priority` の RULE | GDL2 の `when` は and でつなぐ。上から順に最初に当たったもの、という軽い定義の意味は `priority` で表す |
| `round`（丸めの桁） | 式の中の関数（上と同じく未確認） | — |
| `"on": input`（いつ動くか） | **対応なし**（GDL2 の規則が動く条件は `when` の成立だけで、出来事による起動の概念は無い） | 変換では落とす（帳票の側の約束として残す） |
| `editable`（人が上書きできるか） | **対応なし**（出力を編集・上書きできるかの概念は無い） | 同上 |
| 出どころ・レビュー者（2.6） | `GUIDELINE` が継承する `AUTHORED_RESOURCE` の記述（作者・版など）。細目は変換のときに確かめる | — |
| 対応なし | `pre_conditions`（ガイドラインが当てはまる条件。4.3.2）、`predicates`、`default_actions`、`OUTPUT_TEMPLATE`（4.4）、`TERMINOLOGY` の `term_bindings` | 軽い定義にいま無い。乗り換えのときに足すかを決める |
| 書式 | ODIN または JSON（4.3.1） | 軽い定義は YAML。JSON への写しは機械的 |

### 8.2 流れの定義 ↔ Task Planning

Task Planning は土台にしない（R-20261127-16 の 3）。公式の状態は PROC Release 1.7.0 で RETIRED（改訂の記録 SPECPROC-52「Process の仕様をすべて RETIRED にする」）、開発版で PAUSED。

| 軽い定義（3.2） | Task Planning | 備考 |
|---|---|---|
| `flow`（流れ 1 つ） | `WORK_PLAN`（6.2.5.1）が 1 つ以上の `TASK_PLAN`（6.2.5.5）を持つ | 軽い定義は 1 つの流れ = 1 つの TASK_PLAN に当たる |
| `roles`（役割） | `TASK_PARTICIPATION` の `role`（6.2.5.6）。`TASK_PLAN` の `principal_performer` | 仕様に PLAN_ROLE という class は無い |
| `steps`（段） | `TASK`（6.4.2.1）。人が行う段は `PERFORMABLE_TASK`（6.4.2.3） | — |
| 段の `screen`（どの画面で） | `PERFORMABLE_TASK` の `capture_dataset`（`CAPTURE_DATASET_SPEC`。`form_id`・`template_id`。6.6.4.1） | 軽い定義の画面は帳票より広い（一覧やグラフを含む）。変換では帳票の画面だけが対応する |
| `next`（次の段。1 つ） | `TASK_GROUP` の `execution_type` = sequential（6.3.7.1・6.3.7.2） | — |
| `next`（複数。人が選ぶ） | `ADHOC_GROUP`（人が枝を選ぶ。6.7.5.8） | — |
| 条件による分岐 | `CONDITION_GROUP`・`DECISION_GROUP`（6.7.5.4〜7） | 軽い定義はいま持たない |
| 遷移（画面の `open`・`then`） | **対応なし**（Task Planning は段の並びで、画面の中のボタンの遷移を持たない） | 遷移は画面の定義の側に残る |
| 待ち・時刻・出来事 | `TASK_WAIT`・`EVENT_WAIT`・`TIMER_EVENT` など（6.9.6） | 軽い定義はいま持たない |
| 計測（4 節） | **対応なし**（`execution_history` は実行の記録で、時間の集計の概念ではない） | — |

## 9. 承認のときに足したこと（R-20261127-21）

- 定義の YAML は安全な読み方だけで読む（別名と任意のクラスを許さない）。大きさの上限を決める（値は D-1 で決め、spec で pin する）
- 流れの定義は、設計の図と計測の鍵に使う。患者ごとの進み具合は、いまは持たない（3.2 節）
- ロジックの有効化（2.6 節）: レビューの前のロジックで計算した値が、記録に保存されないことを、作りと spec で示す
  （画面で計算した値が、そのまま送られて保存される道を閉じる）。D-6 のゲートで、作りを報告する
- 例の `source` と `reviewed_by` は、記録で確かめられるものだけを書く。確かめられないものは、例と分かる書き方にする
  （実在の人の名前を、確かめずにレビュー者として書かない。2.6 節の例を直した）。
  BMI の区分の出どころの「4.0 版」が何を指すかは、D-6 の前に人間に確かめる（臨床の判断）
- あとの段の候補: 生成 AI が書いた定義が、検査を通る割合を測る（測定の計画は別。いまは実装しない）
