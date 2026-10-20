# デモ機セットアップ手順（原稿、`skoba/anlage#47`）

リハ・本番で「既知の初期状態」から始めるための手順。環境前提の空欄は人間が埋める（plan 5 節）。
参照は **template_id** で行い、dev DB の id には依存しない（裁定 2026-10-12）。

## 1. 前提（確定版、2026-10-12 統括供給）

| 項目 | 値 | 根拠 |
|---|---|---|
| デモ機 | Vaio Z または Vaio S14。リハ 1（10/25）で Z を試し本番機を決定。もう一台は予備機として会場へ（両機とも本手順で同一状態にし、切替は HDMI 差し替えのみ） | 統括 |
| 実行環境 | WSL2（Ubuntu）上で Rails、Windows 側 Chrome で `localhost:3000` | 統括 |
| Ruby | 4.0.7（rbenv。`.ruby-version`、`Dockerfile` `ARG RUBY_VERSION`） | `893aa7f` |
| Node／sushi | Node 18 ＋ fsh-sushi 3.16.0（`rake fsh:verify` 用、任意） | 統括、`lib/tasks/fsh.rake:50` |
| Chromium | system spec（`js: true`）用。壇上の表示は Windows 側 Chrome | 統括、`spec/rails_helper.rb:12` |
| DB | SQLite（development、`storage/development.sqlite3`）。`rake demo:reset` で既知状態へ。所要 **3.1 秒／2.8 秒**（サンプル投入込み、本開発機で 2 回実測、2026-10-20。デモ機では再計測して上書き） | 実測 |
| ネットワーク | **オフライン前提、外部呼び出し無し**。importmap は gem 同梱の turbo／stimulus、CDN 無し。CKM URL 取り込みと `fsh:verify` は台本に乗せない | `config/importmap.rb`、`templates_controller.rb:162-185` |
| 表示 | 会場は 16:9・HDMI-A・解像度不明 → **設計値 1280×720**。ブラウザは 1280×720 相当（表示スケーリングで調整）、ミラーリング（複製）モード。system spec のビューポートを 1280×720 で pin（ナビ折返し・表幅・横スクロール無し） | 統括、plan 6 節 |
| 荷物 | 予備機・HDMI ケーブル・USB-C→HDMI 変換・電源 | 統括 |
| 復旧手順 | サーバ再起動 → `bin/rails demo:reset` → 台本の第 1 幕から | 統括 |

## 2. 初期状態を作る

```sh
bundle install
bin/rails db:prepare          # 初回・schema 更新時
bin/rails demo:reset          # fixture 5 件を active で登録、記録を消してサンプルのカルテ記録だけにする
bin/rails server
```

`demo:reset` の到達状態（`spec/tasks/demo_reset_spec.rb` で固定）:

- `Template.active` = CardiologyEncounter／LabResultReport／ProblemList／bmi_calculation／**patient_blood_pressure.v1**（template_id はファイル名と一致しない）、全て v1.0.0・saveable・pathcards 生成済み
- superseded 無し、jp_referral 無し（第 1 幕で壇上登録する）
- サンプルのカルテ記録（`Demo::SampleCompositions`、裁定 D 2026-10-12・裁定 2026-10-20）: `compositions`＝5（ProblemList 2〔「2型糖尿病」ICD-11 5A11 付き・「高血圧症」自由記述〕・CardiologyEncounter 1〔120/80〕・LabResultReport 1〔空腹時血糖 98 mg/dL〕・bmi_calculation 1〔170 cm／65 kg〕）、RM グラフの Composition＝6（上の 5＋jp_referral 1〔「2型糖尿病」5A11 付き、テンプレート未登録のまま RM グラフにだけ入る〕）
- デモクエリ 5（`docs/demo/aql-queries.md` 5 節）は初期状態で 3 件、壇上で 1 件足すと 4 件
- 何度実行しても同じ（リハの合間に打ち直してよい）。production では abort

## 3. 壇上で使うファイル

- `spec/fixtures/opt/jp_referral.opt`（第 1 幕で取り込む。sem_ver 0.2.0）
- `docs/demo/aql-queries.md`（第 3 幕で貼るクエリ 4 件。engine console の既定文字列はクエリ 1 と同文）
- `tmp/fsh/`（第 4 幕、`bin/rails fsh:export` の出力）

## 4. 確認（リハ前）

```sh
bundle exec rspec                 # 実ブラウザ system spec を含む全 suite（Chromium がある機で）
bin/rails demo:reset              # 打ち直し
```

Chromium が無い機では `bundle exec rspec --tag '~js'` と CI（`test` ジョブ）の green で代替する。
