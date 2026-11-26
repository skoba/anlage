# 任意の Basic 認証: 計画

裁定 ID: R-20261126-2（4）。Issue: #163。状態: **案（push して、そのまま進む。R-20261124-8）**。

- 基準点: anlage main `f6df2bd`
- 「実測」は anlage のツリーと、`Gemfile.lock` が指す gem を読んだ結果

## 1. ねらい

v0.2.0 は、利用者の登録とログインを付けずに出す（裁定）。外から届く場所で動かしてしまったときの最低限の守りとして、
環境変数で利用者名とパスワードを与えたときだけ、全画面と API に Basic 認証をかける。与えなければ、いまと同じ動き。

## 2. いまの状態（実測）

- 画面は anlage の controller（`ApplicationController` の子）と、openehr-rails の engine（`mount OpenehrRails::Engine => "/openehr"`、
  `config/routes.rb:2`）に分かれる。engine の controller は anlage の `ApplicationController` を継がない
  （AQL 照会、FHIR、openEHR REST）。そのため、controller の `http_basic_authenticate_with` では engine に届かない
- ヘルスチェックは `GET /up`（`rails/health#show`、`config/routes.rb:7`）
- Docker の手順は README の「動かし方」（`docker run … -e SECRET_KEY_BASE=…`）

## 3. 方針

1. **Rack のミドルウェアで全体にかける**。Rails が依存している rack の `Rack::Auth::Basic` を使い、gem は足さない。
   アプリの入口でかけるので、anlage の画面、engine の画面と API、静的なファイルのどれにも効く
2. 環境変数は `ANLAGE_BASIC_AUTH_USERNAME` と `ANLAGE_BASIC_AUTH_PASSWORD`。
   - **両方を与えたときだけ**かける。どちらも与えなければ、いまと同じ（ミドルウェアは何もしない）
   - 片方だけを与えたときは、起動を止める（`ArgumentError`）。かけたつもりで開いたまま動く状態を作らない
   - 空の文字列は、与えていないものとして扱う
3. 比べるときは、時間の差で漏れない比べ方（`ActiveSupport::SecurityUtils.secure_compare`）を使う
4. **`/up` はかけない**。ロードバランサやコンテナのヘルスチェックは認証情報を持たない。`/up` が返すのは起動しているかだけで、
   患者のデータを含まない
5. realm は `Anlage`
6. Docker の手順（README）に、`-e ANLAGE_BASIC_AUTH_USERNAME=… -e ANLAGE_BASIC_AUTH_PASSWORD=…` の例と、
   「Basic 認証は TLS の上で使う（平文で送られる）」を書く。既知の制限の 1 に、この選択肢を書き足す

## 4. 実装

- `lib/middleware/optional_basic_auth.rb`（`OptionalBasicAuth`）。設定のときに使うので autoload の外に置き（`autoload_lib` の ignore に `middleware`）、`config/application.rb` で require する:
  `initialize(app, username:, password:)`。両方あれば `Rack::Auth::Basic` で包み、`/up` は素通し。無ければ素通し
- `config/application.rb`: `config.middleware.use OptionalBasicAuth, username: ENV[…], password: ENV[…]`
- spec:
  - ミドルウェアの単体（`Rack::MockRequest`）。認証情報なし → 401、正しい → 200、違う → 401、`/up` → 200、
    未設定 → 素通し、片方だけ → 起動で `ArgumentError`
  - アプリのミドルウェアの列に入っていること（環境変数を与えないテスト環境では素通し）

## 5. 範囲の外

- 利用者の登録、ログイン画面、記録の監査（誰が書いたか）への結び付け: v0.2.0 のあとに設計から（裁定）
- 利用者ごとの権限
