# Phase 3 デモ統合ログ（`skoba/anlage#47`）

4 幕（OPT 取り込み → フォーム入力 → AQL → FHIR/FSH）＋パスカード検索を壇上で一本の流れとして歩けるようにする
Phase 3 の進行記録。計画: `docs/design/demo-integration-plan.md`。連番節 R1〜。

---

## R1: explore（実測）と `rake demo:reset` 第一実装（2026-10-12）

### 0. 環境の実測（本開発機、WSL2）

- Ruby: 作業中に `.ruby-version` が 4.0.6 → **4.0.7** に切り替わった（人間側の追随、`893aa7f`。openehr-ruby `a02fa1d`・openehr-rails `32a79e7` も同日）。本節の実測は前半が 4.0.6 bundle、後半（`demo:reset` の dev 実行・ルート走査・FHIR 計測）が 4.0.7 bundle。
- **申告**: 4.0.6 の bundle が本機に無く suite を起動できなかったため、Claude Code が 4.0.6 で `bundle install` を実行した（リポジトリ内のファイルは不変。4.0.7 への移行で不要になった操作）。
- dev DB（`storage/development.sqlite3`）は本機では**空**だった（10/5 の clone 以降未構築。各文書にある id=5/6 の jp_referral は旧機の状態）。→ 2 節の `demo:reset` で構築。**dev DB の id は環境ごとに違うので、spec・台本・docs の参照は template_id で行う**（裁定 2026-10-12）。
- Chrome／Chromium・chromedriver は本機に無い（`which` で全て不在）。`js: true` の system spec はローカルで走らせられず、CI（`.github/workflows/ci.yml` `test` ジョブ、ubuntu-latest）を判定器とする（裁定 3）。Chromium の導入は人間側。
- 非ブラウザ suite: `bundle exec rspec --tag '~js'` → **169 examples, 0 failures, 3 pending**（`demo:reset` の 2 例を含む）。`bin/rubocop` 96 files, 0 offenses。
- オフライン前提の確認: importmap は gem 同梱の `turbo.min.js`／`stimulus.min.js` をピン（`config/importmap.rb`）、layout に CDN・外部フォント無し（`app/views/layouts/application.html.erb`）。ネットワークが要るのは CKM URL 取り込み（`templates_controller.rb:162-185`）と `rake fsh:verify`（sushi）だけで、どちらも台本に乗せない。

### 1. 画面・ルート棚卸し（`config/routes.rb`）

| 画面 | ルート | 遷移先リンク（実測） | 備考 |
|---|---|---|---|
| カタログ（取り込み） | `GET /`＝`templates#index` | 各カードの `/forms/:template_id` のみ（`_template.html.erb:4`「Open form」） | 見出し「Templates」。ドロップ／ファイル選択／URL 取り込み（`index.html.erb`） |
| 試着室（プレビュー） | `POST /templates/preview`（turbo-frame 内） | 「登録」「破棄」ボタンのみ | 見出し「試着室: <template_id>」（`preview.html.erb:1`） |
| 帳票 | `GET /forms/:template_id` | **無し**（links=[]、`<nav>` 無し） | 見出しはテンプレート名、ボタン「送信」（`forms/show.html.erb:17`） |
| 保存後 | `POST /compositions/:template_id` → 302 → `GET /compositions/:id` | **無し**（links=[]） | flash `notice: "登録しました"` は set されるが（`compositions_controller.rb:34`）layout に表示が無く**映らない**（`application.html.erb:26-28` は `yield` のみ）。本文は `<h1>template_id</h1>`・作成時刻・canonical JSON の `<pre>`（`compositions/show.html.erb:1-4`） |
| 記録一覧 | `GET /compositions` | 各記録へのリンクのみ | 見出し「Compositions」 |
| パスカード検索 | `GET /pathcards/search?q=` | **無し**（カードにリンク無し。`_pathcard.html.erb`） | 見出し「Pathcard search」、ラベル「Query」、ボタン「Search」。q=血圧 で 2 件（dev、fixture 5 件） |
| AQL | `GET /openehr/query`（gem の engine console） | gem の nav（Templates／AQL Query／Patients） | dev で 200（認証ゲートは dev/test を素通し）。textarea の既定クエリは gem 固定文字列で、**`?q=` の事前入力は無い**（gem `app/views/openehr_rails/queries/show.html.erb:9`）。既定文字列はデモクエリ 1（height）と同文 |
| FHIR | `GET /fhir/r5/StructureDefinition/:id` | JSON | id はテンプレート単位ではなくアーキタイプ単位（下表） |

共通ナビは**どの画面にも無い**。各画面はブラウザの「戻る」でしか行き来できない。

### 2. 人間の摩擦リストの再現と根本原因（file:line）

1. **保存後にメニュー無し・遷移が不自然**: 再現（integration session、dev、rollback）: `POST /compositions/CardiologyEncounter` → 302 → `/compositions/1`（links=[]、flash 文言は本文に無し）。原因は (a) `app/views/compositions/show.html.erb:1-4` に次アクションのリンクが無い、(b) `app/views/layouts/application.html.erb:26-28` に共通ナビと flash 表示が無い。
2. **ドロップ領域が分かりにくい**: `app/assets/stylesheets/application.css` は Rails 生成時のコメントのみ（10 行、`2aaba37` 以来変更無し）。`dropzone_controller.js:48,54,60` が `overlay` に `.visible` を付け外しするが**対応する CSS が存在しない**ため、`#dropzone_overlay`「Drop the .opt file to try it on」は常時平文で表示され、ドラッグ中も何も変わらない。`#dropzone_hint`（クリックでファイル選択）も平文で、ボタンに見えない。受付直後のファイル名表示は無い（`queueStatus` は「残り n 件」のみ、`:81-83`）。`docs/plans/opt-dropzone.md:328` は「dragenter オーバーレイ」を計画していたが CSS は実装されなかった。
3. **「試着室」**: `preview.html.erb:1`・spec 4 本（`opt_dropzone`／`url_dropzone`／`multi_file_dropzone`／`requests/templates_spec:46`）が文言を固定。UI 文言の棚卸しは 4 節。
4. **登録版 v1.0.x と出所版**: 登録版は `app/models/template.rb:29` の固定 `"1.0.0"` と `next_version`（`:48-52`、patch 連番）。OPT 側の版は `description/other_details[@id='sem_ver']` にあり、パーサが `opt.description.other_details["sem_ver"]` で返す（実測: jp_referral `"0.2.0"`、ProblemList `"0.2.1"`。openehr-ruby `lib/openehr/parser/opt_parser.rb:93-110`）。**web_template には載っておらず**、画面にも出ない（`_template.html.erb:3`・`preview.html.erb:4,20`）。
5. **BMI**: `bmi_calculation` の field（実測、`Template.build_from_opt_xml`）: `height`（身長 cm、number、required）／`body_weight`（体重 kg、number、required）／`body_mass_index`（Body mass index、number、units 2 択 `kg/m2`・`[lb_av]/[in_i]2`、required）／`body_mass_index_at0013`（判定、**DV_TEXT**＝自由記載、任意）。現状は 3 数値を手入力し判定も手入力（`spec/demo/aql_queries_spec.rb:13-14` も直値）。自動計算の仕組みは無い（Stimulus controller は `dropzone` と `hello` のみ）。
6. **CompositionReader の CLUSTER 配下**: `#39`（`153874a`）で対応済み（`composition_reader.rb:42-48`）。本 Phase では対象外。

### 3. `rake demo:reset` 第一実装（裁定 2、解決形 (b)、TDD）

- Red: `spec/tasks/demo_reset_spec.rb`（乱れた状態＝jp_referral 登録・ProblemList の superseded 旧版・Composition 1 件（RM グラフ入り）から 2 回実行 → fixture 5 件 active・pathcards 有・superseded 無・Composition 0・RM 0／production では abort）→ `Don't know how to build task 'demo:reset'` で失敗を確認。
- Green: `lib/tasks/demo.rake`。RM グラフの削除順は gem の関連（`OpenehrRails::Rm::Composition has_many :nodes/:data_values dependent: :delete_all`、`Version belongs_to :composition/:contribution`）に従い data_values → nodes → versions → compositions → contributions → ehrs。登録はドロップゾーン経路と同じ手順（`build_from_opt_xml` → `PathcardExtractor` → `save!`、`templates_controller.rb:68-78` と同型）なので web_template／pathcards は新規導出され、`rebuild_web_template`／`backfill` は不要。
- 実測の訂正 1 点: `patient_blood_pressure.opt` の template_id は **`patient_blood_pressure.v1`**（ファイル名と不一致）。spec の期待値を実測に合わせた。
- dev 実行: `bin/rails db:prepare` → `bin/rails demo:reset` → templates=5（Cardiology 2 fields/2 cards、Lab 3/3、ProblemList 5/6、bmi 4/4、patient_blood_pressure.v1 3/3、全て saveable）、compositions=0、rm_compositions=0。
- 未実装（plan の reset 第二実装）: サンプル Composition の投入（AQL 幕の既知データ）。手順原稿は `docs/demo/setup.md`。

### 4. UI 文言の棚卸し（現状値）

英語と日本語が混在し、同じ対象に複数の呼び名がある: Templates／試着室／テンプレート、Open form／フォームプレビュー／フォーム、送信／登録、Compositions／composition／記録、Pathcard search／Query／Search、Registered:、Drop the .opt file to try it on／Drop an .opt file anywhere, or click to choose、No templates registered yet、archetype検出、記入済みフォーム、テンプレート化しますか、URLから取り込む、閉じる／破棄、保存は未対応（#30）。語彙表の案と適用先は plan 3 節。

### 5. 第 4 幕の実測（FHIR／FSH）

`OpenehrRails::Fhir::ProfileGenerator`／`FshGenerator` の出力（fixture を直接パース）:

| テンプレート | StructureDefinition id | skipped |
|---|---|---|
| CardiologyEncounter | openehr-observation-blood-pressure-v2 | — |
| LabResultReport | openehr-observation-laboratory-test-result-v1 | — |
| ProblemList | openehr-evaluation-problem-diagnosis-v1 | — |
| bmi_calculation | openehr-observation-height-v2／body-weight-v2／body-mass-index-v2 | — |
| patient_blood_pressure.v1 | openehr-observation-heart-rate-pulse-v1／blood-pressure-v1 | — |
| jp_referral | openehr-evaluation-problem-diagnosis-v1／openehr-observation-story-v1 | service_request（0 leaves）・clinical_synopsis ×2（rails #35/#37 の mapping 行待ち） |

`/fhir/r5/StructureDefinition/:id` は `Template.active` 全体から id を探す（`fhir/profiles_controller.rb:24-29`）ので、ProblemList と jp_referral の `openehr-evaluation-problem-diagnosis-v1` は**同 id で先勝ち**（`find`）。壇上で jp_referral の FHIR を見せるなら `openehr-observation-story-v1` を使う（plan 4 節）。FSH は `rake fsh:export` → `tmp/fsh/<template_id>-<version>/input/fsh/<id>.fsh`（`lib/tasks/fsh.rake:27-41`）。

### 6. 上流の状態（読み取りのみ、openehr-rails）

AQL の 0.8.0 同乗分: openehr-rails master `84244cd`、0.7.1 以降 Unreleased に #45（SECTION/INSTRUCTION/ACTIVITY の読み戻し）・#52（rm_type_alternatives）・#49 が入っている（`CHANGELOG.md` Unreleased、PR #51/#53/#54）。リリースは未。Anlage の lock は 0.7.1。締切 10/20 までに 0.8.0 が出なければ既存キャスト（デモクエリ 4 件）のみ（plan 4 節）。

---

## R2: plan 承認（裁定 A〜G＋追加裁定）と文書反映（2026-10-12）

- ゲート報告 (a) に対し統括が plan を承認（判断 A〜G と FHIR id 衝突の追加裁定。`docs/design/demo-integration-plan.md` 9 節に転記）。実装は 10/14〜10/24、リハ 1 10/25、順序は 7 節どおり
- 反映した文書: plan（状態・yml の 6 区分と出典・編集済みフラグ・サンプル Composition 5 件・台本の FHIR 行・9 節）、`docs/demo/ui-vocabulary.md`（新設、正典。「カルテ記録」「帳票に入力」）、`docs/ideas-2027.md`（GDL2 評価器の差し替え点）、`CLAUDE.md`（UI 文言 spec は語彙表に追随）、`docs/backlog.md` 15・`docs/upstream-candidates.md` 23（FHIR id 衝突）、`README.md` Current focus、`docs/demo/setup.md`（D 反映、E 未受領）
- 起票: [skoba/openehr-rails#55](https://github.com/skoba/openehr-rails/issues/55)（FHIR `profile_id` の archetype 単位衝突。裁定により次回覚醒を待たず起票）
- 未受領: 裁定 E の 1 段落（デモ機・オフライン・DB）。届き次第 `docs/demo/setup.md` 1 節へ
- main の CI: scan_ruby は brakeman 8.1.0（`--ensure-latest`）で `893aa7f` から赤のまま（R1 と同じ。dependabot #44 の扱いは未裁定）

---

## R3: 裁定 E 受領（setup.md 1 節の確定版）（2026-10-12）

- `docs/demo/setup.md` 1 節を統括供給の確定版に差し替え（デモ機 Vaio Z／S14・WSL2＋Windows 側 Chrome・Ruby 4.0.7・Node 18＋sushi 3.16.0・Chromium・SQLite・オフライン・設計解像度 1280×720・荷物・復旧手順）。「要確認」「空欄」「未受領」の印を外した
- `demo:reset` 所要の実測: 3.16 秒／2.54 秒（本開発機、2 回。デモ機で再計測して上書き）
- plan: 9 節 E を受領に、5 節の注記を更新、6 節に **system spec のビューポート 1280×720 pin**（ナビ折返し・表幅・横スクロール無し）を追加——変更 1 の spec で固定する

---

## R4: openehr-rails 0.8.0 同乗（裁定 B、2026-10-20）

- 裁定（2026-10-20）: 0.8.0 同乗は最初に。順序 0.8.0 bump → scan_ruby 緑化 → 変更 1 → 2 → 3 → 5 → 4。リハ 1 は 10/26 へ（凍結 11/5 不変）
- `bundle update openehr-rails --conservative`: 0.7.1 → 0.8.0（openehr は 2.4.3 のまま）。`Gemfile.lock` CHECKSUMS `openehr-rails (0.8.0) sha256=d9068d3ed4252fd33f0cfb4e25506118787235ae7d8ade203a7063087e5c7aa6` == openehr-rails `docs/reports/referral-upstream-log.md` R8 の公開値
- `jp_referral_aql_spec` 構造骨格: pending のまま。ただし失敗点が移った——上流 15 項（to_rm の NoMethodError）は解消し、`CONTAINS INSTRUCTION … AND EVALUATION` は束縛まで通る。新たに `items[openEHR-EHR-CLUSTER.organisation.v1, '紹介先医療機関']` が 2 件に fan-out（openehr 2.4.3 `path_evaluator.rb:117-118` が ArchetypePredicate の name 値を捨てる）→ 上流候補 24 項（openehr-ruby）。pending 理由を 24 項に付け替え
- 含意（第 3 幕）: name 述語を使う jp_referral の AQL は 0.8.0 でも壇上に出せない。第 3 幕に jp_referral を入れるか（入れるなら name 述語を使わないクエリ形）は裁定待ち
- 全 suite（ローカル）: 177 examples, 8 failures, 3 pending。8 件は全て `js: true` の system spec で chromedriver 127.0.0.1:9515 への接続拒否（Chromium 未導入、既知の環境要因）。判定は CI の `test` ジョブ

---

## R5: scan_ruby 緑化（裁定、2026-10-20）

- 裁定: dependabot #44 と同内容を直接コミットし、`--ensure-latest` を外す（凍結中の外部要因 red の排除）。残りの dependabot PR は superseded でクローズ
- `bundle update brakeman --conservative`: 8.0.6 → 8.1.0（`Gemfile.lock` の差分は #44 と同一。sha256 `cfa9e521…fdc17e07`）
- `--ensure-latest` は `ci.yml` ではなく `bin/brakeman:5`（Rails 既定 binstub の `ARGV.unshift`）にあった。そこを外して理由コメント 1 行に置き換えた（`ci.yml` は `bin/brakeman --no-pager` のまま）
- ローカル: `bin/brakeman --no-pager` → No warnings found、`bin/bundler-audit` → No vulnerabilities found

---

## R6: 例外報告（R4）への裁定と上流 24 項の起票（2026-10-20）

- 裁定: 第 3 幕に jp_referral を name 述語なしの「傷病名で引く」横断クエリで入れる／上流 24 項は即起票／変更 5 に jp_referral 1 件（ICD-11 コード付き）。plan 6 節 3' 行・5 節・9 節に転記
- 実測（scratchpad の使い捨て spec、構造骨格を直接コミット → `to_rm`）: `protocol.items_at_path("/items[openEHR-EHR-CLUSTER.organisation.v1]")` → 2 件、`"…organisation.v1, '紹介先医療機関']"` → 1 件（RM 側は name で絞れる）。`SELECT ev/data[at0001]/items[at0002]/value/value … CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]` → `[["2型糖尿病"]]`（name 述語なしなら jp_referral を AQL で読める＝3' 行の前提）
- 起票: [skoba/openehr-ruby#60](https://github.com/skoba/openehr-ruby/issues/60)（bug）。openehr-ruby `docs/backlog.md` Round 2 magazine に首位群の行を追加（docs のみの越境、openehr-ruby master `96eb4e2`）
- 未決（設計上の自明な選択として plan 5 節に記載）: jp_referral のサンプルはフォーム保存経路（#30 で未対応）ではなく `CompositionCommitter` の直接コミット

---

## R7: 変更 1（共通ナビ・flash・保存後の次アクション）（2026-10-20）

- TODO: (1) `Template#fhir_profile_ids` (2) layout の nav が全画面に (3) 保存後のカルテ記録画面（flash・見出し・次アクション 4・JSON 折りたたみ） (4) 実ブラウザの操作列＋1280×720 pin (5) 既存 spec と語彙表の追随
- (1) Red: `NoMethodError`（2 例）→ Green: facade と同じ `ProfileGenerator.new(OpenehrRails::Opt.parse(source_xml)).profiles` の id。ProblemList `["openehr-evaluation-problem-diagnosis-v1"]`、patient_blood_pressure.v1 は heart-rate-pulse → blood-pressure の順（R1 5 節の実測と一致）
- (2)(3) Red: `spec/requests/demo_navigation_spec.rb` 4 例が全て失敗（nav 不在・`#flash` 不在・次アクション `[]`・`details > pre` 不在）→ Green: layout に `nav#app_nav`（AQL 照会は `openehr_rails.query_console_path`＝`/openehr/query`）と `#flash`、flash を「保存しました」、`compositions/show` に見出し・保存日時・`nav#next_actions`・`<details>`
- (5) rack_test の `forms_spec` は JSON 文字列ではなく flash と見出しで確認する形へ。実ブラウザの `demo_problem_list_spec`／`demo_lab_result_spec` は summary「canonical JSON」を開いてから JSON を見る（閉じた `<details>` の中は不可視）。語彙表に共通ナビ・次アクション・保存日時・canonical JSON を追記
- (4) `spec/system/demo_save_next_actions_spec.rb`（CardiologyEncounter: 保存 → flash・見出し・次アクション 4 → nav が 1 行・横スクロール無し〔JSON を開いても〕→「もう 1 件」で空の帳票へ）、`rails_helper` の js before で `resize_to(1280, 720)`。横スクロールの判定は plan の `<= 1280` ではなく `scrollWidth > window.innerWidth`（ウィンドウ枠の分だけ内寸が 1280 より狭くなり得るため）
- Red の扱い: ローカルは Chromium 不在に加え chromedriver が `libnspr4.so` を読めず起動しない。spec を main ではなくブランチ `change1-system-spec`（draft PR #51）に載せて CI で判定 → run `39433188399` green（184 examples, 0 failures, 3 pending）。**CI で red にならなかったので、(4) は (2)(3) の Red で駆動済みの挙動を実ブラウザで固定する pin**（実装を先に壊して red を作ることはしていない）。main は同ブランチへ fast-forward

---

## R8: 変更 2（取り込み画面）（2026-10-20）

- TODO: (a) `Template#sem_ver` (b) カード・プレビュー・supersede 文の版並記 (c) プレビュー見出し＋説明 1 行 (d) CSS・「ファイルを選択」主導線・ページ全体のドロップ (e) 受付表示（JS）
- (a) Red: `NoMethodError`（2 例）→ Green: `opt.description.other_details["sem_ver"].presence` を web_template に。fixture の実測: jp_referral 0.2.0／ProblemList 0.2.1／LabResultReport 0.2.0／bmi_calculation 0.2.0／CardiologyEncounter 0.1.0／patient_blood_pressure は要素無し → nil
- (b)(c)(d) Red: `spec/requests/template_intake_spec.rb` 6 例が全て失敗（見出し「試着室」・`#version_label` 不在・supersede 文が `v1.0.0` のみ・カードに `.version-label` 不在・`button#dropzone_hint` 不在・CSS 空）→ Green: `TemplatesHelper#version_label`（「登録版 v1.0.0／テンプレート版 0.2.0」、sem_ver 無しは登録版のみ）、supersede 時の登録予定版は `next_version`、ドロップは `@window`（layout に controller を上げない）、`application.css` に `#dropzone_overlay`（既定 none／`.visible` で fixed・inset 0・`pointer-events: none`）・ボタン・カード枠のみ。CSS は asset パスの本文で pin
- (e) `opt_dropzone_spec` → `demo_intake_spec` に改名・拡張（台本 1 幕、jp_referral.opt）。**Red は CI で確認**: ブランチ `change2-intake`（draft PR #52）に spec だけの一時コミットを push → run `39436740715` red（`#queue_status` が空で「受付: jp_referral.opt」が見つからない、1 failure）。Green: `showStatus` で受付直後「受付: <名前>（解析中…）」→ プレビュー後「（確認待ち）」→ 登録／破棄で次へ（残り件数は同じ行に続ける）。一時コミットは Green と squash し main には残さない
- 1 回目の Green（run `39436895531`）は spec 側の不備で red: 空になった `<p id="queue_status">` は高さ 0 で Capybara が不可視とみなし `exact_text: ""` が見つからない → `not_to have_css(…, text: "受付")` に修正 → run `39437122540` green（192 examples, 0 failures, 3 pending）
- 判断: plan は「試着室表示で消す」だったが、プレビュー中は「確認待ち」を残し、登録／破棄で消す形にした（壇上でいま何を確認しているかが見え、spec が一瞬の表示を追わずに済む）
- 変更 3 に送ったもの: 一覧の h1「Templates」・空状態文・オーバーレイ文言「Drop the .opt file to try it on」・「archetype検出」・カードの「Open form」（語彙表の置換元。一括適用で扱う）

---

## R9: 変更 3（UI 語彙表の一括適用）（2026-10-20）

- 語彙表を先に直した: 置き換え先が表に無かった置換元に置き換え先を決めて追記（オーバーレイ「ドロップして取り込む」、解析ログ「アーキタイプ検出: <名前>（<N> 項目）」、要約「アーキタイプ数・項目数」、「帳票プレビュー」、カルテ記録の空状態「カルテ記録はまだありません。」、パスカードの項目名「テンプレート・アーキタイプ・ノード」と警告「未翻訳の疑いがあります」、ADL の説明文）。**正典への追記なので確認を求める**
- Red: `spec/requests/ui_vocabulary_spec.rb`（6 例）と旧文言 pin の書き換え（request 4 本）で 10 failures → Green: view 10 ファイル＋`dropzone_controller.js` の解析ログ。js 以外 189 examples, 0 failures
- system spec の文言追随（「送信」→「保存」4 本、demo_intake の空状態・解析ログ、polymorphic 2 例）はブランチ `change3-vocab`（draft PR #53）で CI 判定 → run `39437772748` green（198 examples, 0 failures, 3 pending）。main は fast-forward
- 台本 6 節「検索」行の 1 行変更（パスカードから帳票へのリンク「帳票に入力」）も同じコミットで入れた（ui_vocabulary_spec で pin）
- 対象外として残した英語: `POST /templates` の二重登録通知（`already registered as …`、JSON API の `notice`、`templates_spec.rb:194` が pin）とアップロードエラーのメッセージ。壇上の操作列には出ない（プレビューの段階で「登録済み」を出すため）

---

## R10: 変更 5（demo:reset 第二実装・デモクエリ 5）（2026-10-20）

- 順序は裁定どおり 3 → 5（変更 4 BMI は最後）
- 実測（scratchpad の使い捨て spec）: (1) `SELECT c/archetype_details/template_id/value …` → `unsupported path attribute "archetype_details" on a …Composition`（上流候補 25 項として記録）。出所の並記は `c/name/value`（Composition 名＝テンプレート名）で代替 (2) ProblemList「高血圧症」（フォーム経路）＋「2型糖尿病」（at0002 を DV_CODED_TEXT 5A11 に差し替えて直接コミット）＋jp_referral 骨格で、横断クエリが `[["ProblemList","高血圧症"],["ProblemList","2型糖尿病"],["jp_referral","2型糖尿病"]]`
- **裁定 D との差**: 「ICD-11 コード付き 1＝at0002 を coded で」は `Opt::RmCompositionCommitter`（フォーム経路）では作れない。ProblemList の at0002 は `coded_free` で、builder は常に DV_TEXT にする（`composition_builder.rb:185`）。フォーム経路の canonical の at0002 だけを DV_CODED_TEXT に差し替えて直接コミットした（Anlage の `compositions` にも同じ canonical で 1 行入れ、カルテ記録一覧に出る）
- jp_referral のサンプル: テンプレートは初期状態に含めない（第 1 幕で壇上登録）ので、RM グラフにだけ直接コミット（カルテ記録一覧には出ない）。骨格は `jp_referral_aql_spec` から `spec/fixtures/compositions/jp_referral/skeleton.canonical.json` に切り出して共有（Refactor コミット、spec の結果は不変）。傷病名は reset 側で DV_CODED_TEXT 5A11 に差し替える
- Red: `demo_reset_spec`（サンプル 5＋RM 6・傷病名 3 種）と `spec/demo/cross_template_query_spec.rb`（初期 3 件・1 件足して 4 件）で 4 failures → Green: `Demo::SampleCompositions.load!`（`app/lib/demo/sample_compositions.rb`）を reset の transaction 内で呼ぶ
- Green 途中の発見: フォーム経路の Composition は RM の `template_id` 列が nil。`Opt::CompositionBuilder#build` がルートに `archetype_details` を付けず、`archetype_node_id` に template_id を入れている（`composition_builder.rb:35-37`）→ (b) 課題 [#54](https://github.com/skoba/anlage/issues/54)。spec は RM 側を `name_value` で見る形にした。凍結前に直すかは裁定事項
- js 以外 192 examples, 0 failures, 3 pending。dev の `bin/rails demo:reset` 3.14 秒／2.80 秒（2 回、`templates=5 compositions=5 rm_compositions=6`）。`docs/demo/setup.md` を更新
- 文書: `docs/demo/aql-queries.md` 5 節、`docs/demo/setup.md` 2 節、plan 5 節、`docs/upstream-candidates.md` 25 項


---

## R11: 変更 4（BMI form_behaviors、4 薄切り）（2026-10-20）

- 1/4 `Opt::Formula`: Red `uninitialized constant` → Green。初回 Green で `-2 ^ 2` が 4 になった（単項マイナスを累乗より強く結合させていた）→ 文法を `unary := "-" unary | power`、`power := primary ("^" unary)?` に直して 5 例 green（右結合 `2 ^ 3 ^ 2 = 512`、未知の識別子・関数・記号は `Opt::Formula::Error`）
- 2/4 `Opt::FormBehaviors`＋`config/form_behaviors.yml`（plan 4 節の宣言そのまま）: Red `uninitialized constant` → Green 15 例（170/65 → 22.5・普通体重、editable: false の上書き、editable: true の空欄のみ補完、`__edited` で埋めず values から除く、inputs 欠けは不計算、日本肥満学会 6 区分の境界 8 点〔「未満」で切る〕、宣言無しは不変、`rules_for`）
- 3/4 controller: Red（送った BMI 99 がそのまま保存）→ `CompositionsController#create` で `FormValidator` の前に `FormBehaviors.apply` → Green。既存デモクエリ 1（BMI 21.6・判定 "normal" を送る）は BMI が再計算値に置き換わるだけで件数不変
- 4/4 クライアント: request spec（帳票が rules を data 属性で渡す）は**ローカルで Red** → 実装中に発見: **YAML 1.1 では鍵 `on:` が真偽値 `true` になる**（plan 4 節の宣言のままだと rules の鍵が `true`）→ `"on":` と引用、`rules_for` の spec に `"on" => "input"` を足して pin。system spec `demo_bmi_spec`（170/65 → 22.5 readonly・普通体重 → 保存 → AQL `> 170` 0 行／`>= 170` 1 行。判定を手で直した後に身長を 180 に直しても判定は手の値のまま、BMI は 20.1）は **CI で Red**（ブランチ `change4-bmi-client`、draft PR #55、run `39439469971`: 予定の 3 failures）→ Green（run `39439764042`、226 examples, 0 failures, 3 pending）。一時コミットは squash
- 評価器は Ruby（`app/lib/opt/formula.rb`）と JS（`form_behaviors_controller.js` の `evaluateFormula`）の 2 実装。同じ値になることは BMI の 2 例（22.5／20.1）で画面値として固定。丸めは JS 側も Ruby の `Float#round` と同じく 0 から遠い側
- #47 の受入 (6) を満たす

---

## R12: 台本「検索」行の system spec と台本対応表の充足（2026-10-20）

- 実測（scratchpad、jp_referral と ProblemList を登録して `Opt::PathcardSearch`）: 「既往歴」→ jp_referral at0004「病歴の記述」／「傷病名」→ jp_referral at0002「プロブレム・診断の名称」・at0077・at0073（ProblemList のカードはこの語では当たらない）
- `spec/system/demo_pathcard_search_spec.rb`: 検索 → カード → 「帳票に入力」→ `/forms/jp_referral` が閲覧専用（「保存は未対応（#30）」、保存ボタン無し）。挙動は変更 3 までに実装済みのため **pin**（ブランチ `script-search-spec`、draft PR #56、run `39440313208` green、227 examples, 0 failures, 3 pending）
- 台本対応表（plan 6 節）の各行と spec:

| 幕 | spec | 状態 |
|---|---|---|
| 1 取り込み | `spec/system/demo_intake_spec.rb` | green（R8、Red は CI） |
| 検索・1' 閲覧専用 | `spec/system/demo_pathcard_search_spec.rb` | green（本節、pin） |
| 2 帳票（BMI） | `spec/system/demo_bmi_spec.rb` | green（R11、Red は CI） |
| 2 保存後の次アクション | `spec/system/demo_save_next_actions_spec.rb` | green（R7、pin） |
| 2' ProblemList | `spec/system/demo_problem_list_spec.rb` | green（文言追随） |
| 3 AQL | `spec/demo/aql_queries_spec.rb`（1〜4） | green |
| 3' 横断 AQL | `spec/demo/cross_template_query_spec.rb`（5） | green（R10） |
| 4 FHIR／FSH | `spec/requests/fhir_profiles_spec.rb`・`spec/tasks/fsh_spec.rb`（既存） | green |

- 3 幕の AQL コンソール（`/openehr/query`、gem の画面）そのものを操作する system spec は無い（plan 6 節どおり、件数は `Executor` で固定）。壇上の打鍵はリハ 1 で確かめる
