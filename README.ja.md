# Anlage（日本語）

[English](README.md) | 日本語

> **参照実装です。認証がありません。実在の患者のデータを入れないでください。外から届く場所で動かさないでください。**
> (This is a reference implementation without authentication. Do not enter real patient data, and do not expose it to an untrusted network.)

## Anlage(原基)とは

**臨床モデル（OPT）を置くと、コード生成もサーバ再起動もなしにEHRが動き出す。**

Anlageは、openEHR仕様に基づくEHRの参照実装である。

## 何を達成しようとしているか

Anlage（原基）は、すべての EHR の原基になることを目指す。臨床のモデル（openEHR のアーキタイプとテンプレート）の上に、
ロジック、画面と流れ、利用者の層を、どれも**定義**として持ち、**実行時に置く**。コードを生成せず、サーバを止めずに、
定義を置いた瞬間に EHR が形を変える。

いま動いているのは、その最初の層: Operational Template を置くと、帳票・検証・保存・AQL・FHIR のプロファイルが立ち上がる。
次は、患者を開くとカルテに見える画面（定義が無くても既定の画面が立ち上がり、定義で上書きできる）と、テンプレートと一緒に置くロジック。

4層構成で成り立つ: `openehr-ruby`（RM/AMの純Rubyライブラリ）→
`openehr-rails`（Rails統合層・RM永続化・AQL）→
`openehr-rails-startup`（アプリケーション生成器）→ **Anlage**（本リポジトリ、
生成された参照実装そのもの）。

将来的には、CKM（Clinical Knowledge Manager）で統制された臨床知識を意味基盤
として、OPTから抽出した意味索引（パスカード）を通じた検索、さらにLLMの
接地（grounding）先として使えるところまでを見据えている——ただしこれは
**将来形**であり、以下の「今どこまで動くか」とは明確に区別する。

## 今どこまで動くか（実測ベース）

以下は`spec/`のテストまたは`docs/evidence/`のスクリーンショットで裏付けが
取れているものに限る。

- **OPTドロップ→フォーム生成・検証・保存**: OPTを投入すると、フォームが
  動的に構築され、送信値の検証・保存が行われる
  （[`app/lib/opt/form_validator.rb`](app/lib/opt/form_validator.rb)、
  [`app/lib/opt/composition_builder.rb`](app/lib/opt/composition_builder.rb)、
  [`spec/lib/opt/composition_builder_spec.rb`](spec/lib/opt/composition_builder_spec.rb)）
- **FHIR R5ファサード**: 登録済みテンプレートをFHIR形式で公開する
  （[`app/controllers/fhir/`](app/controllers/fhir/)）
- **パスカード抽出（スキーマv1）**: OPT投入時に全ノードから意味索引カードを
  抽出する（[`docs/design/pathcards-schema-v1.md`](docs/design/pathcards-schema-v1.md)、
  [`docs/demo/opt-catalog.md`](docs/demo/opt-catalog.md)）
- **AQL照会**: シード経路とフォーム保存経路から
  `OpenehrRails::Rm::CompositionCommitter`経由でRMグラフへ投入したCompositionを
  AQLで照会できる
  （[`spec/demo/aql_queries_spec.rb`](spec/demo/aql_queries_spec.rb)、
  [`spec/requests/compositions_spec.rb`](spec/requests/compositions_spec.rb)、
  [`docs/demo/aql-queries.md`](docs/demo/aql-queries.md)）。RMグラフがAQLの権威ストアで、
  Anlageの`compositions`テーブルはarchival・原本表示専用の非権威ストアである。
  既知の到達性の
  制約（コード値WHERE・イベント時刻WHEREが現行AQLエンジンでは不可）は
  [`docs/upstream-candidates.md`](docs/upstream-candidates.md) 10・11項参照。
- **デモクエリのspec化**: 会話記録に依存しない、実行可能な形でのデモクエリ4本
  （[`docs/demo/aql-queries.md`](docs/demo/aql-queries.md)）
- **SECTION・INSTRUCTION・複数ルートを持つテンプレートの保存**: 診療情報提供書（jp_referral）を帳票から保存し、
  紹介先医療機関と傷病名を AQL で引ける（[`spec/system/demo_referral_spec.rb`](spec/system/demo_referral_spec.rb)）。
  必須の規則は「入れ物を書くなら必須」（[`docs/design/required-rule.md`](docs/design/required-rule.md)）
- **テンプレートの管理**: 詳細・版の履歴・2 つの版の差分（項目とパスカード）
  （[`spec/requests/template_detail_spec.rb`](spec/requests/template_detail_spec.rb)、
  [`spec/requests/template_diff_screen_spec.rb`](spec/requests/template_diff_screen_spec.rb)）
- **患者（EHR）とカルテ記録**: 患者を作って選び、保存した記録をその EHR に結び付ける（患者を選ばないと保存できない）。記録の修正（openEHR の版）と
  論理削除（[`spec/requests/patients_spec.rb`](spec/requests/patients_spec.rb)、
  [`spec/requests/records_to_ehr_spec.rb`](spec/requests/records_to_ehr_spec.rb)、
  [`spec/requests/record_versions_spec.rb`](spec/requests/record_versions_spec.rb)、
  [`spec/requests/record_delete_spec.rb`](spec/requests/record_delete_spec.rb)）
- **パスカード検索とクエリビルダー**: 項目を言葉で探し、表示する項目と条件を選ぶと AQL が組まれ、検査を通してから実行される
  （[`docs/design/s2-query-builder-plan.md`](docs/design/s2-query-builder-plan.md)）

できないこと・気を付けることは [`docs/known-limitations.md`](docs/known-limitations.md)（**認証が無い**ので、実在の患者のデータを入れない）。

## 動かし方

### 開発機（Ruby 4.0.10）

```sh
bundle install
bin/rails db:prepare
bin/rails server          # http://localhost:3000
bundle exec rspec         # テスト（system spec に Chrome が要る）
```

### Docker

イメージは本番用の設定（`RAILS_ENV=production`）。`config/master.key` が無くても、`SECRET_KEY_BASE` を渡せば起動する。
データ（SQLite）は `/rails/storage` に置かれるので、volume にする。
Basic 認証（下の「任意の Basic 認証」）を与えて起動する形を、先に書く。

```sh
docker build -t anlage .
docker run -d --name anlage -p 8080:80 \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -e ANLAGE_BASIC_AUTH_USERNAME=demo -e ANLAGE_BASIC_AUTH_PASSWORD='<長いパスワード>' \
  -v anlage-storage:/rails/storage anlage
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/up                                 # 200（/up に認証はかからない）
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/patients                          # 401
curl -s -o /dev/null -w "%{http_code}\n" -u demo:'<長いパスワード>' http://localhost:8080/patients   # 200
```

初期データ（fixture のテンプレート 5 本と、架空の患者 9 人・84 件のサンプル）を入れるときは、
**全データを消して入れ直す**操作なので、環境変数で明示する:

```sh
docker exec -e ANLAGE_ALLOW_DEMO_RESET=1 anlage bin/rails demo:reset
```

http://localhost:8080/ を開き（利用者名 `demo` とパスワードを入れる）、テンプレートの画面に OPT を取り込む。試しの OPT は
[`spec/fixtures/opt/`](spec/fixtures/opt/)（出所は [`docs/demo/opt-catalog.md`](docs/demo/opt-catalog.md)）。

**文で問う（LLM）は、既定でオフ。** クエリビルダーは、日本語の問いから、LLM で「表示する項目」と「条件」を選べる
（AQL を組んで検査するのは Anlage）。外の API を呼ぶのは、次が**すべて**そろったときだけで（鍵だけではオンにならない）、
呼び出すたびに費用がかかる:

```sh
  -e ANLAGE_LLM=anthropic -e ANLAGE_LLM_MODEL='<モデルの ID>' -e ANTHROPIC_API_KEY='<鍵>' \
  -e ANLAGE_LLM_DAILY_CALL_LIMIT=100   # 任意。1 日に呼んでよい回数（既定 100）
```

API に送るのは、問いの文と、候補の項目の名前。記録の中身は送らない。anlage の画面には認証が無いので、オンにした Anlage に
届く人は、だれでも、1 日の上限まで API を呼べる。どちらの会社に文が送られるかは `ANLAGE_LLM` で決まる: OpenAI を使うときは
`ANLAGE_LLM=openai` と `OPENAI_API_KEY`（`ANTHROPIC_API_KEY` の代わり）。`ANLAGE_LLM=local`（Ollama）と `ANLAGE_LLM=lmstudio`（LM Studio）は、同じ機械の中のサーバーを使い、
外には何も送らない。詳しくは [`docs/nl-query.ja.md`](docs/nl-query.ja.md)。

#### API を Postman で試す

[`docs/demo/postman/`](docs/demo/postman/) に、Postman のコレクション（v2.1）と環境の雛形がある。
FHIR（CapabilityStatement、StructureDefinition）と openEHR REST（EHR の取得、AQL の実行、記録の取得）の 5 件。

1. Postman で `anlage.postman_collection.json` と `anlage.postman_environment.json` を取り込み、環境「Anlage（ローカルの Docker）」を選ぶ
2. 環境の `password` に起動時の `ANLAGE_BASIC_AUTH_PASSWORD` を、`ehr_id` に患者の画面の EHR ID（「EHR ID を写す」）を入れる。パスワードは雛形に書き込んで commit しない
3. 「AQL の実行」を送ると、応答の 1 行目の記録の uid が `composition_uid` に入る。そのあと「記録の取得」を送る

認証はコレクションの Basic 認証 1 か所で、各要求はそれを引き継ぐ。FHIR の Observation は、anlage ではいつも 0 件になるので入れていない（[既知の制限](docs/known-limitations.md) 19）。

#### 任意の Basic 認証

Anlage には利用者の登録とログインが無い。環境変数で利用者名とパスワードを**両方**与えたときだけ、
全画面と API（AQL 照会、FHIR、openEHR REST）に Basic 認証をかける（`/up` はかけない）。
片方だけを与えると起動しない。Basic 認証は平文で送られるので、TLS の上で使う。
これは最低限の守りで、実在の患者のデータを入れてよいことにはならない
（[`docs/design/basic-auth-plan.md`](docs/design/basic-auth-plan.md)）。

与えずに起動したとき（`ANLAGE_BASIC_AUTH_*` を外した `docker run`）:

- openehr-rails の engine（AQL 照会の画面、`/openehr/fhir`、`/openehr/v1` の openEHR REST）は、production では
  認証の設定が無いと 403 を返す（gem の既定）。与えたときは、入口で認証済みとして engine を開ける（`config/initializers/openehr.rb`）
- **anlage の画面（患者、帳票、カルテ記録、パスカード検索、クエリビルダー、FHIR プロファイル）は、認証なしで開いたままになる**。
  誰でも全患者の記録を見て、作り、修正し、削除できる（[既知の制限](docs/known-limitations.md) 6b）

## Current focus

（2026-11-27 更新。公開 v0.2.0 のリリースの PR）

- **v0.2.0**: 患者（EHR）とカルテ記録の修正・削除・記録の中身、クエリビルダー（版をまたいで引く）、パスカード検索の別名表、
  任意の Basic 認証、Docker と初期データ（架空の患者 9 人・84 件）、Postman のコレクション。変更の一覧は [`CHANGELOG.md`](CHANGELOG.md)
- 受け入れ: 台本 [`docs/demo/acceptance-v0.2.0.md`](docs/demo/acceptance-v0.2.0.md) を人間が画面で通した（2026-11-27）。
  指摘の 3 点（記録の中身、EHR ID を写す、Postman）を入れたあと、変わる行をまっさらな Docker で通し直した
  （[`docs/reports/acceptance-v0.2.0-log.md`](docs/reports/acceptance-v0.2.0-log.md) R3・R4）
- 依存: openehr 2.6.1／openehr-rails 0.12.0、Ruby 4.0.10
- できないこと: [`docs/known-limitations.md`](docs/known-limitations.md)（**認証と認可が無い**。実在の患者のデータを入れない）
- **次**: good first issue の起票（`docs/reports/v0.2.0-prep-log.md` の候補 G1〜G7）。患者 ID から EHR を引く入口と、
  問いを入れた AQL の画面（openehr-rails の次の版）が出たら、「この患者の記録を AQL で引く」リンクを足す

## 進行の追い方

- **Issues**: 着手前・発覚時にGitHub Issueを立てる運用（実装目標=goal、
  課題=problem）。テンプレートは[`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/)
- **[`docs/demo/opt-catalog.md`](docs/demo/opt-catalog.md)**: デモ・テストで
  使うOPT fixtureの一覧（出所・チェックサム・状態）
- **[`docs/upstream-candidates.md`](docs/upstream-candidates.md)**: Anlageで
  発見した知見をgem側（openehr-ruby/openehr-rails）へ還流する観察ログ。
  実際の還流実績: `openehr-rails 0.4.1`、`openehr 2.3.1`/`2.3.2`/`2.4.0`/`2.4.1`
- **[`docs/reports/`](docs/reports/)**: 各フェーズ・Issueの進行ログ（実測記録）
- **[`docs/evidence/`](docs/evidence/)**: 動作確認のスクリーンショット等の証跡

## ライセンス・コミュニティ

NPO法人 openEHR Japan が定期的にオンライン例会を開催している
（[connpass](https://openehr-japan.connpass.com/)）。

外部からのIssue・貢献の受け入れは準備中（Issueテンプレートは整備済み。
正式受付は追って告知）。
