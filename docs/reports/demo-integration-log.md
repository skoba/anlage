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
