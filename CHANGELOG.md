# 変更履歴

Anlage は openEHR の参照実装である。値は合成で、患者は架空。実在の患者のデータを入れない（[既知の制限](docs/known-limitations.md)）。

## v0.2.0（2026-11-27）

前の版はタグ `v0.1.0-jcmi46`（2026-11-18、医療情報学連合大会のチュートリアルで動いた版）。
この節は、`changelog.d/` の断片（PR ごとの変更履歴）をまとめたもの。依存は openehr 2.6.1、openehr-rails 0.11.0、Ruby 4.0.10。

### 利用者に見える変更

#### 患者とカルテ記録

- 患者（EHR）の画面（`/patients`）。患者 ID を入れると EHR が 1 つできる。患者は患者 ID と名前空間 `anlage` だけを持つ（#130）
- いまの患者を選ぶ（「この患者を選ぶ」「選択を外す」。選択はセッションに持つ）（#134）。帳票の保存は、いまの患者の EHR に結び付く（#136）。
  患者を選ばないと保存できない（帳票に注記が出て、保存のボタンが出ない。POST は 422）（#161）
- 患者の画面に、その患者の EHR の記録をすべて、記録日の新しい順に出す。テンプレートが登録されていない記録は、閲覧だけの画面
  （`GET /patients/:id/records/:uid`）で項目の名前と値を見られる（#182）
- 患者の画面の EHR ID の横に「EHR ID を写す」（押すとクリップボードに入る）（#192）
- カルテ記録の修正（同じ uid の新しい版。「版の履歴」。`GET /compositions/:id/edit`、`PATCH /compositions/:id`）（#138）と、
  論理削除（`DELETE /compositions/:id`。削除した記録は一覧・患者の画面・AQL の結果から外れる）（#140、#177）
- カルテ記録の画面に「記録の中身」。帳票と同じ入れ子の見出しとラベルで、値のある項目を読める。古い版はその版の値。
  帳票に読み戻せない記録は、名前と値の表（#191）

#### 帳票と保存

- 帳票の入力欄を、ルート（SECTION → ENTRY → 埋め込み CLUSTER）ごとの入れ子の枠にまとめ、テンプレート上の名前を見出しにした（#119）
- 同じアーキタイプの複数ルートを区別し（2 つめ以降の項目名に `_2`・`_3`）、jp_referral（診療情報提供書）を帳票から保存できるようにした（#117、#80、#30）。
  紹介先医療機関の項目に紹介元の名前が付いていたのを直した
- 必須の規則を「入れ物を書くなら必須」に改めた（任意の枠の中の必須は「※」。帳票全体が空なら保存しない）（R-20261125-1）
- openehr-rails 0.9.0 で、ENTRY の protocol の要素も帳票の項目になる（ProblemList に「最終更新日」）（#111）
- 保存する Composition の形を直した: ルートの `archetype_node_id` と `archetype_details`（#54）、`terminology_id` の値（#86）、
  `category` の表示とコード（#87）、ノードの名前をテンプレートの用語から（#109）、`context/start_time`（保存した時刻。修正と削除の版は元の時刻を引き継ぐ）（#146）。
  保存済みの記録は変えない
- OBSERVATION を含む記録が、保存から 1 秒たつと修正できなくなっていたのを直した（#171）
- 取り込んだ記入済みの帳票で、自由記述の傷病名が空欄になっていたのを直した（#82）

#### テンプレート

- テンプレートの詳細（`GET /templates/:template_id`）と版の履歴（`GET /templates/:template_id/versions/:version`）（#98）、
  2 つの版の差分（項目とパスカード。`GET /templates/:template_id/diff`）（#100）
- FHIR プロファイルへのリンクを、カルテ記録の画面からテンプレートの詳細に移し、すべてのプロファイルを並べた（#102）
- openehr-rails 0.10.0 で、FHIR プロファイルの id と URL がテンプレートで修飾された形になった
  （例 `/fhir/r5/StructureDefinition/openehr-problemlist-evaluation-problem-diagnosis-v1`）（#146）

#### 検索とクエリビルダー

- クエリビルダー（`/queries/new`）。パスカードを探して表示する項目と条件に足すと AQL が組まれ、検査（リンタ）を通してから実行される（S2）。
  条件は数値比較、値集合のコード（「未記入を含む」）、日付の範囲、文字列、「範囲の外」、「または」でつなぐ
- 「版をまたいで引く」（`config/version_mappings.yml` のレビュー済みの行。血圧の収縮期・拡張期の v1・v2 が有効）（#154）
- 出所の列は記録の template_id（「テンプレートも表示する」、列の見出し「テンプレート」）（#183）
- パスカード検索: 別名表（`config/search_aliases.yml`。レビュー済みの行だけ）と、別名で出たときの理由の表示、
  特定できない語の案内（#152）。score に当たった項目の重みを入れた（#127）。同点の並びを登録順によらず一定にした（#122）

#### 画面と運用

- 画面を左ナビと作業面の 2 列にした。AQL 照会（engine の画面）にも同じナビが出る（#95）
- どの画面にも、ナビの先頭に参照実装の警告（「参照実装です。認証がありません。…」）（#162）
- 任意の Basic 認証（`ANLAGE_BASIC_AUTH_USERNAME` と `ANLAGE_BASIC_AUTH_PASSWORD` を両方与えたときだけ。`/up` にはかからない）（#163）。
  与えたときは、production でも engine（AQL 照会・FHIR・openEHR REST）を開ける（#174）
- Docker のイメージがビルドできなかったのを直した（`libffi-dev`）。README に「動かし方」（#142）
- `ANLAGE_ALLOW_DEMO_RESET=1` を与えたときだけ、production（Docker）でも `rake demo:reset` を実行できる（#168）
- 初期データ（`rake demo:reset`）: 架空の患者 9 人（DEMO-01〜09）、84 件（#144、#179。血液内科への紹介の例を含む）
- API を Postman で試すコレクション（`docs/demo/postman/`。FHIR 2 件、openEHR REST 3 件）（#193）

#### 依存

- openehr 2.4.3 → 2.6.1、openehr-rails 0.8.0 → 0.11.0（#90、#111、#146、#177）、Ruby 4.0.7 → 4.0.10。AQL でコード値・イベント時刻・name 述語・
  template_id に届き、削除した記録が AQL から外れる（既知の制限 13・18 の解消）

### 開発者向けの変更（画面・保存・API は変わらない）

- 評価 v2（`rake evaluation:run`。card と aql の 2 種の問い、レビュー済みのゴールド、S2 の経路、版をまたぐ問い、負例だけの問い）。
  まとめは `docs/evaluation-summary.md`
- AQL のリンタ `QueryBuilder::Linter`
- テンプレートの用語を openehr 2.5.0 の `CArchetypeRoot#term_definitions` から取り、XML の読み直し（`Opt::TemplateTerms`）を撤去した（#104）

### 文書

- 既知の制限の一覧 `docs/known-limitations.md`（認証が無い、日付の表示は日本時間に固定、FHIR の Observation は anlage では 0 件、など）
- 受け入れの台本 `docs/demo/acceptance-v0.2.0.md` と、まっさらな Docker で通した記録 `docs/reports/acceptance-v0.2.0-log.md`（#173）
- 設計書と計画書（`docs/design/`）、上流の候補（`docs/upstream-candidates.md` 29〜31 項）
