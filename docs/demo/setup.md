# デモ機セットアップ手順（原稿、`skoba/anlage#47`）

リハ・本番で「既知の初期状態」から始めるための手順。環境前提の空欄は人間が埋める（plan 5 節）。
参照は **template_id** で行い、dev DB の id には依存しない（裁定 2026-10-12）。

## 1. 前提

| 項目 | 値 | 根拠 |
|---|---|---|
| Ruby | 4.0.7（`.ruby-version`、`Dockerfile` `ARG RUBY_VERSION`） | `893aa7f` |
| DB | SQLite、`storage/development.sqlite3`（`config/database.yml`） | 実測 |
| JS | importmap。gem 同梱の turbo／stimulus をピン、CDN 無し → **オフラインで動く** | `config/importmap.rb`、layout |
| ネットワークが要る操作 | CKM URL 取り込み（台本に無い）、`rake fsh:verify`（sushi、任意） | `templates_controller.rb:162-185`、`fsh.rake:43-64` |
| ブラウザ | Chrome／Chromium（壇上）。`js: true` system spec のローカル実行にも同じものが要る | `spec/rails_helper.rb:12` |
| デモ機 | （空欄: 機種・OS・解像度） | 人間 |
| オフライン運用 | （空欄: 会場回線の有無・ローカルのみで走らせるか） | 人間 |

## 2. 初期状態を作る

```sh
bundle install
bin/rails db:prepare          # 初回・schema 更新時
bin/rails demo:reset          # fixture 5 件を active で登録、Composition・RM グラフを空にする
bin/rails server
```

`demo:reset` の到達状態（`spec/tasks/demo_reset_spec.rb` で固定）:

- `Template.active` = CardiologyEncounter／LabResultReport／ProblemList／bmi_calculation／**patient_blood_pressure.v1**（template_id はファイル名と一致しない）、全て v1.0.0・saveable・pathcards 生成済み
- superseded 無し、jp_referral 無し（第 1 幕で壇上登録する）
- `compositions`＝0、`openehr_rm_*`／`openehr_ehrs`＝0
- 何度実行しても同じ（リハの合間に打ち直してよい）。production では abort

（plan の第二実装で追加予定: AQL 幕の既知データ＝サンプル Composition の投入。裁定 D）

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
