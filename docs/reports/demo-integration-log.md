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
