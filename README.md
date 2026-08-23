# Anlage

Anlage ("foundation"/"disposition" in German) is a reference implementation of
an openEHR-based EHR, generated from openehr-rails-startup. Its core claim:
drop a clinical model (an Operational Template) in, and a form, validation,
persistence, and a FHIR facade come alive at runtime — no code generation
step in between. This README describes what is actually running today
(with evidence links) separately from where the project is headed.

## Anlage(原基)とは

**臨床モデル（OPT）を置くと、コード生成もサーバ再起動もなしにEHRが動き出す。**

Anlageは、openEHR仕様に基づくEHRの参照実装である。

## 何を達成しようとしているか

Anlageが実証しようとしているのは、openEHR標準の役割の転換である。標準を
「アプリケーション開発時に**採用するもの**」から、実行時に**置くと動き出す
もの**へ変えること——Operational Templateを投入した瞬間に、フォーム・検証・
永続化・FHIRファサードが動的に立ち上がる、という二層モデリングの実証実験。

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
- **AQL照会**: デモ用にシード経路（`OpenehrRails::Rm::CompositionCommitter`
  直接呼び出し）で投入したCompositionをAQLで照会できる
  （[`spec/demo/aql_queries_spec.rb`](spec/demo/aql_queries_spec.rb)、
  [`docs/demo/aql-queries.md`](docs/demo/aql-queries.md)）。既知の到達性の
  制約（コード値WHERE・イベント時刻WHEREが現行AQLエンジンでは不可）は
  [`docs/upstream-candidates.md`](docs/upstream-candidates.md) 10・11項参照。
  **フォーム保存経路からAQLへの合流は未対応**
  （[`skoba/anlage#10`](https://github.com/skoba/anlage/issues/10)で対応中）
- **デモクエリのspec化**: 会話記録に依存しない、実行可能な形でのデモクエリ4本
  （[`docs/demo/aql-queries.md`](docs/demo/aql-queries.md)）

## Current focus

保存経路の修復: `skoba/anlage#9`（シード/Committer経路のarchetype_details欠落）は解消済み。
残るは`skoba/anlage#10`（フォーム保存経路がAQLの照会対象に合流していない）→ 次は検索層（WP3）。

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
