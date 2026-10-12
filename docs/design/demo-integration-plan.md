# 計画: Phase 3 デモ統合 — 4 幕＋パスカード検索を壇上で一本の流れとして歩ける（`skoba/anlage#47`）

- Issue: `skoba/anlage#47`（goal）。関連: `#30`（jp_referral の保存経路、preview_only の根拠）、`#39`（CompositionReader、対応済み）、`#23`（jp_referral 受入）
- 状態: **承認済み（2026-10-12、裁定 A〜G＋追加裁定。9 節）**。実装 10/14〜10/24、リハ 1 10/25。先行実装は `rake demo:reset` 第一実装（`docs/reports/demo-integration-log.md` R1 3 節）。語彙の正典は `docs/demo/ui-vocabulary.md`
- 日程: 実装 10/14〜10/24、リハ 1 10/25、凍結 11/5。AQL の 0.8.0 同乗は締切 10/20
- 変更は 6 種に限定: **共通ナビ／保存後の次アクション／取り込み画面／UI 語彙表の一括適用／BMI form_behaviors／demo:reset**。新機能は BMI のみ。各場面を実ブラウザ system spec 1 本で固定する（台本対応表の行＝spec の操作列）

## 0. 探索結果（実測、file:line。詳細は log R1）

1. 共通ナビ・flash 表示が無い: `app/views/layouts/application.html.erb:26-28`（`yield` のみ）。全画面が孤立
2. 保存後に次アクションが無い: `app/views/compositions/show.html.erb:1-4`。`compositions_controller.rb:34` の `notice: "登録しました"` は映らない（302 → links=[] を再現）
3. ドロップ領域: `app/assets/stylesheets/application.css` が空で `.visible` 不在。`dropzone_controller.js:48,54,60` の付け外しが無効、オーバーレイ文言が常時平文。ファイル名／状態表示無し（`:81-83` は残件数のみ）
4. 版の並記: 登録版は `template.rb:29,48-52`（`1.0.0`＋patch 連番）。出所版は `opt.description.other_details["sem_ver"]`（jp_referral `0.2.0`、ProblemList `0.2.1`）で取れるが web_template に無い
5. BMI: `bmi_calculation` の field 名は `height`／`body_weight`／`body_mass_index`（units 2 択）／`body_mass_index_at0013`（判定、DV_TEXT 自由記載）。計算の仕組みは無い。Stimulus は `pin_all_from "app/javascript/controllers"` で自動登録
6. AQL: engine console `/openehr/query` は dev で 200。`?q=` の事前入力は無い（gem の view `queries/show.html.erb:9` 固定文字列＝デモクエリ 1 と同文）
7. FHIR: `/fhir/r5/StructureDefinition/:id` の id はアーキタイプ単位。ProblemList と jp_referral の problem-diagnosis は同 id で先勝ち（`fhir/profiles_controller.rb:24-29`）→ jp_referral は `openehr-observation-story-v1` を見せる
8. UI 文言を固定している spec: 「試着室」4 箇所、「登録」ボタン 5 箇所、「送信」4 箇所、「No templates registered yet」3 箇所、「登録済み」2 箇所、「記入済みフォーム」「テンプレート化しますか」各 2 箇所（log R1 の grep）。語彙の一括適用は spec の同時更新を伴う
9. 名前空間の衝突掃引（規律: 追加名の掃引）: 追加する Stimulus controller 名 `form-behaviors`、設定ファイル `config/form_behaviors.yml`、クラス `Opt::FormBehaviors`／`Opt::Formula`、web_template キー `sem_ver`、view の `nav`／`flash` は `app/ lib/ config/` と spec の Ruby ファイルに不在（`grep -rn "form_behaviors\|FormBehaviors\|Formula\|sem_ver\|form-behaviors" app lib spec config`、実測）。出現は fixture の中だけ: OPT 本文の term 文言「Formula」（bmi at0010、CardiologyEncounter／patient_blood_pressure の MAP 説明）と `jp_referral.golden.json:7` の `_provenance.template_version` 文字列、各 OPT の `other_details id="sem_ver"`（Cardiology 0.1.0／Lab 0.2.0／ProblemList 0.2.1／bmi 0.2.0／jp_referral 0.2.0）。いずれもレジストリ（web_template の field キー・除外リスト等）ではなく、追加名が捕捉する対象は無い。web_template に足すキーは `sem_ver` のみで、既存キー（`template_id`／`concept`／`entries`／`form_capability`／`form_capability_reason`）と衝突しない

## 1. 変更 1: 共通ナビ＋flash（layout）と保存後の次アクション

- layout に `<nav>`（テンプレート／カルテ記録一覧／パスカード検索／AQL 照会）と flash 表示を足す。AQL は `/openehr/query` への外部リンク（engine 側 nav は gem のまま）
- `compositions/show`: 見出し「カルテ記録: <テンプレート名>」、flash「保存しました」、次アクション（同じ帳票にもう 1 件入力 `/forms/:template_id`／カルテ記録一覧／AQL 照会／FHIR プロファイル `/fhir/r5/StructureDefinition/<先頭 id>`）。canonical JSON は折りたたみ（`<details>`）
- spec: `spec/system/demo_save_next_actions_spec.rb`（js: true。CardiologyEncounter を保存 → flash と 4 リンクが見える → 「もう 1 件」で帳票に戻る）＋request spec（layout の nav が全画面に出る）

## 2. 変更 2: 取り込み画面

- CSS（`application.css` に初めて実スタイルを入れる）: `#dropzone_overlay` は既定 `display: none`、`.visible` で全画面オーバーレイ。`#dropzone_hint` をボタン風の主導線「ファイルを選択」に。カード・フォームの最低限の余白のみ（デザインはしない）
- 受付直後の表示: `queueStatus` に「受付: <ファイル名>（解析中…）」→ 試着室表示で消す（`dropzone_controller.js` `preview` 前後）
- 見出し「試着室: id」→「テンプレートの取り込み: <テンプレート名>」＋説明文 1 行（「登録前に中身を確認します」）
- 版の並記: `Template.build_web_template` が `sem_ver` を web_template に載せる（`opt.description.other_details["sem_ver"]`、無ければ nil）。カード・試着室・supersede 文に「登録版 v1.0.0／テンプレート版 0.2.0」。既登録分は `demo:reset`（dev）または `templates:rebuild_web_template` で追随
- spec: `opt_dropzone_spec`（文言更新＋受付表示＋版の並記）、Template spec（`sem_ver`）、view spec（オーバーレイの class 切替は JS なので system spec 側で `have_css("#dropzone_overlay.visible", visible: false)` は使わず、CSS の存在は `spec/requests` で stylesheet 本文を読む pin で足りる）

## 3. 変更 3: UI 語彙表の一括適用（正典 `docs/demo/ui-vocabulary.md`、裁定 F で確定）

| 対象 | 画面見出し | ボタン／ラベル | 台本での呼び名 | 現状（置換元） |
|---|---|---|---|---|
| テンプレート（OPT） | テンプレートの取り込み | ファイルを選択／URLから取り込む／登録／破棄 | テンプレート | Templates／試着室／Drop the .opt file…／Drop an .opt file anywhere… |
| 帳票（フォーム） | <テンプレート名> | 帳票に入力／保存 | 帳票 | Open form／送信 |
| カルテ記録（Composition） | カルテ記録一覧／カルテ記録: <テンプレート名> | 保存しました | カルテ記録（「カルテ記録として保存」） | Compositions／composition／Registered:／登録しました |
| パスカード | パスカード検索 | 探したい項目／検索 | パスカード | Pathcard search／Query／Search／Template／Archetype／Node |
| AQL 照会 | （gem の console） | AQL 照会（nav） | AQL 照会 | AQL Query |
| FHIR プロファイル | — | FHIR プロファイル（リンク） | FHIR プロファイル | — |
| FSH | — | — | FSH 出力（`rake fsh:export`） | — |
| 空状態 | — | テンプレートが未登録です。OPT ファイルを選択して取り込んでください | — | No templates registered yet… |
| 取り込み結果 | 記入済みの帳票／アーキタイプ（テンプレートではありません） | 閉じる | — | 記入済みフォーム／ADLアーキタイプ |

- 適用は 1 コミット（view と spec の文言を同時に。裁定 G: 文言 pin は regression pin ではなく語彙表の写しなので語彙表と同一コミットで更新）。CLAUDE.md に「UI 文言を固定する spec は `docs/demo/ui-vocabulary.md` に追随する」を追記済み

## 4. 変更 4: BMI form_behaviors（新機能はこれだけ）

- 宣言 `config/form_behaviors.yml`（template_id → behaviors）:

```yaml
# 帳票の振る舞い（skoba/anlage#47）。rules は GDL2 の rule/when と同型で、12 月の GDL 評価器導入時は
# この yml を GDL2 ガイドラインへ差し替える（docs/ideas-2027.md）。式は安全サブセットのみ（plan 4 節）
bmi_calculation:
  - target: body_mass_index
    inputs: [height, body_weight]
    formula: "body_weight / (height / 100) ^ 2"   # kg, cm → kg/m2（units は select の先頭 kg/m2 を前提）
    round: 1
    on: input
    editable: false        # 画面は readonly、サーバが常に再計算（権威）
  - target: body_mass_index_at0013
    inputs: [body_mass_index]
    # 出典: 日本肥満学会「肥満症診療ガイドライン」の肥満度分類（BMI 区分、4.0 版の表記）。WHO 文言は採らない
    cases:
      - when: "body_mass_index < 18.5"
        value: 低体重
      - when: "body_mass_index < 25"
        value: 普通体重
      - when: "body_mass_index < 30"
        value: 肥満（1度）
      - when: "body_mass_index < 35"
        value: 肥満（2度）
      - when: "body_mass_index < 40"
        value: 肥満（3度）
      - else: 肥満（4度）
    on: input
    editable: true         # 提案。空欄のときだけサーバが埋め、編集済みは尊重
```

- 式は GDL2 互換の安全サブセット: 数値・識別子（inputs 名）・`+ - * / ^`・括弧・`round(x, n)`・比較 `< <= > >= == !=`。`eval` は使わず `Opt::Formula`（再帰下降、トークン集合を閉じる）で評価。未知の識別子・関数は `Opt::Formula::Error`
- サーバ: `Opt::FormBehaviors.apply(template, values)` を `CompositionsController#create` の `FormValidator` の**前**に通す（`compositions_controller.rb:21`）。`editable: false` の target は inputs が揃えば上書き、`editable: true` は blank のときだけ埋める。builder は変えない（値は values に入って従来経路で保存される）
- 編集済みフラグ（裁定 C 追加）: `editable: true` の target を人間が書き換えたら、クライアントは hidden `values[<target>__edited]=1` を立て、以後の再計算でその target を上書きしない（壇上で判定を手で直した直後に身長を直しても提案が戻らない）。サーバも `__edited` が立っていれば blank 補完をしない。system spec で pin
- クライアント: `app/javascript/controllers/form_behaviors_controller.js`。`forms/show` が `data-form-behaviors-rules-value` に yml 由来 JSON を出し、`input` イベントで同じ式を JS 側の小評価器で計算して target に書く。**評価器は 2 実装**（Ruby／JS）になるので、yml の式例を両方で同じ値にする spec（Ruby: unit、JS: system spec で画面値）を置く。GDL2 評価器本体は 12 月（`docs/ideas-2027.md` へ退避）
- spec: `spec/lib/opt/formula_spec.rb`（四則・累乗・round・比較・エラー）、`spec/lib/opt/form_behaviors_spec.rb`（bmi: 170/65 → 22.5・普通体重、editable の挙動）、request（POST で body_mass_index を書き換えても再計算値で保存）、`spec/system/demo_bmi_spec.rb`（js: 170/65 入力 → 22.5 と判定が即時表示 → 保存 → AQL で height>170 は 0 行、>=170 で 1 行）
- 裁定済み（9 節）: (A) `cases` 承認、(B) 日本肥満学会の 6 区分を正式表記で（else で畳まない）、(C) 上記＋編集済みフラグ

## 5. 変更 5: `demo:reset` 第二実装（第一実装は R1 で済）

- サンプル Composition（裁定 D: 入れる。壇上の入力が 1 件失敗しても第 3 幕が空にならない）: `Opt::RmCompositionCommitter` 経由（フォーム保存経路と同じ値→RM グラフ）で 5 件——ProblemList 2 件（ICD-11 コード付き 1＝at0002 を coded で／自由記述 1＝DV_TEXT。代替制約の実演）、CardiologyEncounter 1、LabResultReport 1（数値 > 50）、bmi 1（170/65）。壇上入力は「1 件足す」演出。jp_referral のサンプルは 0.8.0 bump 後。spec は template_id と件数・AQL の行で固定（`demo_reset_spec` に例を追加）
- `docs/demo/setup.md` 1 節は確定版（裁定 E 受領、2026-10-12）。`demo:reset` の所要はデモ機で再計測して上書き

## 6. 台本対応表（各行＝system spec 1 本の操作列）

| 幕 | 画面 | 操作 | 映るもの | spec |
|---|---|---|---|---|
| 1 取り込み | `/` | 「ファイルを選択」→ jp_referral.opt | 受付表示 → 「テンプレートの取り込み: jp_referral」、アーキタイプ検出ログ、登録版 v1.0.0／テンプレート版 0.2.0、「登録」 | `demo_intake_spec`（opt_dropzone_spec を改名・拡張） |
| 検索 | `/pathcards/search` | 「既往歴」「傷病名」 | jp_referral のカード、カードから帳票へ | `demo_pathcard_search_spec`（カードに `/forms/:template_id` リンクを足す。1 行の view 変更） |
| 1' preview_only | `/forms/jp_referral` | 開く | 「保存は未対応（#30）」、保存ボタン無し | 同上に含める |
| 2 帳票 | `/forms/bmi_calculation` | 身長 170・体重 65 | BMI 22.5・判定「普通体重」が自動、保存 → 記録画面に flash と次アクション | `demo_bmi_spec` |
| 2' | `/forms/ProblemList` | 既存の操作列 | 既存 | `demo_problem_list_spec`（文言のみ更新） |
| 3 AQL | `/openehr/query` | クエリ 1（既定文字列）を実行 | height > 170 の行 | request/integration（engine は gem。spec は `OpenehrRails::Aql::Executor` で件数固定＝既存 `spec/demo/`） |
| 4 FHIR/FSH | HTTP facade は **ProblemList のみ**（`/fhir/r5/StructureDefinition/openehr-evaluation-problem-diagnosis-v1`、カルテ記録画面の「FHIR プロファイル」リンク）。jp_referral は **FSH 出力**（`bin/rails fsh:export` → `tmp/fsh/jp_referral-1.0.0/input/fsh/*.fsh`） | リンク／コマンド | JSON／FSH ファイル | `fhir_profiles_spec`（既存）＋`spec/tasks/fsh_spec`（既存）。id 衝突は rails #55（追加裁定、`docs/backlog.md` 15） |

**ビューポート pin（裁定 E）**: 全 system spec を 1280×720（`page.driver.browser.manage.window.resize_to(1280, 720)` を `rails_helper` の `js: true` before で一括）で走らせ、ナビが折り返さず・表が収まり・横スクロールが無いことを変更 1 の spec で固定する（`page.evaluate_script("document.documentElement.scrollWidth <= 1280")`）。

AQL の 0.8.0 同乗分（SECTION／INSTRUCTION の読み戻しで jp_referral を AQL に出す）は 10/20 までに rails 0.8.0 が出た場合のみ追加（lock bump → `spec/integration/jp_referral_aql_spec.rb` の pending 解除を確認）。出なければ既存キャスト 4 件のまま

## 7. コミット分割と順序（摩擦の大きい順）

1. 変更 1（nav・flash・次アクション）— 10/14
2. 変更 2（取り込み画面・sem_ver）— 10/15〜16
3. 変更 3（語彙一括）— 10/17
4. 変更 4（BMI。Formula → FormBehaviors → controller → Stimulus の 4 薄切り）— 10/19〜21
5. 変更 5（reset 第二実装・setup.md）— 10/22
6. 台本対応表の spec 整理・予備 — 10/23〜24

各コミットは Red→Green、`Refs #47`。DoD: 10/25 リハ 1 までに 6 節の全行が CI green（Chromium 導入後はローカルでも）。`History` 相当は Anlage に無いので log R2〜 に記録

## 8. 承認が要った判断（ゲート、2026-10-12 に裁定済み → 9 節）

A 判定の `cases` 表現／B BMI の閾値・文言／C `editable` の意味／D reset のサンプル Composition／E setup.md の空欄／F 語彙表／G 試着室改名に伴う spec 文言の更新

## 9. 裁定（2026-10-12、統括）

- **A**: 承認。「GDL2 の rule/when と同型」を yml 冒頭コメントと `docs/ideas-2027.md` に残す（12 月の GDL 評価器への差し替え点）
- **B**: 日本肥満学会の区分を 4.0 版の正式表記で: <18.5 低体重／18.5–25 普通体重／25–30 肥満（1度）／30–35 肥満（2度）／35–40 肥満（3度）／≥40 肥満（4度）。else で「2度以上」と畳まない。WHO 文言は採らない（日本の紹介状の語彙＝記録語彙を優先）。出典を yml コメントに 1 行
- **C**: 承認（false＝readonly＋サーバが常に上書き、true＝提案＋blank のみ補完）。加えて「editable: true で人間が上書きした値は再計算で消さない」を system spec で pin（編集済みフラグ）
- **D**: 入れる。ProblemList 2（ICD-11 コード付き 1・自由記述 1）、CardiologyEncounter 1、LabResultReport 1（数値 > 50）、bmi 1（170/65）。壇上入力は「1 件足す」演出。jp_referral は 0.8.0 bump 後
- **E**: 受領（2026-10-12、`docs/demo/setup.md` 1 節に確定版として転記）。デモ機 Vaio Z／S14（リハ 1 で決定、予備機同梱）、WSL2＋Windows 側 Chrome、オフライン、設計解像度 **1280×720**
- **F**: 承認、2 点修正——「記録」→「カルテ記録」、「帳票を開く」→「帳票に入力」。`docs/demo/ui-vocabulary.md` を正典に
- **G**: 承認。語彙表と同一コミットで spec 文言を更新。CLAUDE.md に 1 行追記
- **追加裁定（0 節 7）**: FHIR プロファイル id のアーキタイプ単位衝突は rails 起票（[skoba/openehr-rails#55](https://github.com/skoba/openehr-rails/issues/55)、`docs/upstream-candidates.md` 23 項）。凍結前は anlage 側で「テンプレート修飾 id」を暫定しない。台本では jp_referral の FHIR は FSH 出力で見せ、HTTP facade は ProblemList のみ（`docs/backlog.md` 15、6 節）
- 実装順は 7 節どおり: 保存後動線＋ナビ → 取り込み画面 → 語彙 → BMI → reset 第二実装
