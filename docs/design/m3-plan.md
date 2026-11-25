# M3（ワークベンチ）の計画: gem の公開を待たない分

裁定 ID: R-20261124-10（作業列 5）。状態: **案（push して、そのまま進む。R-20261124-8）**。
対象は、M3 のうち openehr-rails 0.9.0 を待たないもの: 統合レイアウトと、テンプレート管理（一覧・系譜・版差分）。
患者（EHR）とカルテ記録の管理は作業列 7（M2 の出口のあと）で、この計画書には入れない。

- 基準点: anlage main `91715f0`（openehr 2.4.3、openehr-rails 0.8.0。2.5.0 への版上げは PR #92）
- 「実測」は anlage のツリーと、インストール済みの openehr-rails 0.8.0 を読んだ結果

## 1. いまの状態（実測）

- 共通ナビは layout の上部に 4 リンク（テンプレート／カルテ記録一覧／パスカード検索／AQL 照会。
  `app/views/layouts/application.html.erb:27-32`）。スタイルはほぼ無い（`application.css` は 47 行）
- AQL 照会は engine の画面で、engine の layout を使う（openehr-rails 0.8.0
  `app/controllers/openehr_rails/application_controller.rb:5` の `layout 'openehr_rails/application'`）。
  anlage のナビは出ない。行って戻るにはブラウザの「戻る」を使う
- テンプレートの画面は 1 つ（`GET /templates`）。取り込み（ドロップ）と、active なテンプレートのカードが同じ画面にある。
  カードにあるのは名前・template_id・版・「帳票に入力」だけ（`app/views/templates/_template.html.erb`）
- 版の系譜はデータにはある（`templates.status` が `active`／`superseded`、`version` は取り込みのたびに 1 つ上がる。
  `app/models/template.rb:6`・`:48-56`）。画面には出ない。superseded の版を見る手段が無い
- 版の差分は、取り込みのプレビューでだけ出る（`Opt::TemplateDiff`、field の path をキーにした
  追加・削除・変更。`app/views/templates/preview.html.erb`）。登録したあとは見られない。
  パスカードの差分（ラベル・コード・束縛の変化）は、どこにも無い
- FHIR プロファイルへのリンクは、カルテ記録の画面にある（`app/views/compositions/show.html.erb:10-11`）。
  プロファイルはテンプレートから決まるもので、記録ごとには変わらない

## 2. 項目（1 Issue = 1 PR、Red から）

| # | 項目 | Red から始める spec の見出し | 触るファイル |
|---|---|---|---|
| W1 | 統合レイアウト: 左ナビと作業面 | 「どの画面にも、左に同じナビ（テンプレート／カルテ記録一覧／パスカード検索／AQL 照会）が出て、いまの画面の項目に印が付く」「1280×720 で、ナビと作業面が横に並び、横スクロールが出ない」（実ブラウザ） | `app/views/layouts/application.html.erb`、`app/views/layouts/_nav.html.erb`（新規）、`app/assets/stylesheets/application.css`、`spec/requests/demo_navigation_spec.rb`、`spec/system/` |
| W2 | engine の画面（AQL 照会）を同じ layout に入れる | 「AQL 照会の画面にも同じナビが出る」「ナビからテンプレートに戻れる」（実ブラウザ） | `app/views/layouts/openehr_rails/application.html.erb`（新規。engine の layout を anlage の側で上書きする。gem は変えない） |
| W3 | テンプレートの詳細画面と一覧 | 「一覧のカードから詳細に行ける」「詳細に、template_id・登録版・テンプレート版・保存できるか・項目数・パスカードの枚数が出る」「詳細から帳票に入力できる」 | `config/routes.rb`（`GET /templates/:template_id`）、`app/controllers/templates_controller.rb`、`app/views/templates/show.html.erb`（新規）、`_template.html.erb` |
| W4 | 系譜（supersede） | 「詳細に、同じ template_id の版が新しい順に並び、有効な版に印が付く」「置き換えられた版の詳細も開ける（帳票への入力は出ない）」 | W3 と同じ。`GET /templates/:template_id/versions/:version` |
| W5 | 版差分の画面 | 「2 つの版を選ぶと、追加・削除・変更された項目が出る」「パスカードの差分（ラベル・コード束縛の変化）が出る」「差分が無ければ、その旨が出る」 | `app/lib/opt/pathcard_diff.rb`（新規）、`app/views/templates/diff.html.erb`（新規）、`GET /templates/:template_id/diff` |
| W6 | FHIR プロファイル／FSH をテンプレートの詳細に移す | 「詳細に、そのテンプレートの FHIR プロファイルへのリンクが出る」「カルテ記録の画面からは、テンプレートの詳細へのリンクに変わる」 | `app/views/templates/show.html.erb`、`app/views/compositions/show.html.erb`、`spec/requests/demo_navigation_spec.rb` |

補足:

- **W1・W2**: 文言は変えない（ナビの 4 項目はそのまま）。位置と見た目だけが変わる。
  `docs/demo/ui-vocabulary.md` の「共通ナビ」の行は、置き場所（左）を書き足す
- **W2 のやり方**: Rails は layout を、アプリの `app/views` から先に探す。anlage に
  `app/views/layouts/openehr_rails/application.html.erb` を置けば、engine の画面がそれを使う（推論。W2 の Red で確かめる）。
  engine の画面の中では anlage の URL ヘルパーは `main_app.` を付けて呼ぶ。ナビは共通の partial にして、
  両方の layout から使う
- **W3**: URL の `:template_id` は、いまの `forms/:template_id` と同じ制約（`/[^\/]+/`、`format: false`）にする。
  一覧（`GET /templates`）の取り込みの機能は変えない。カードに「詳細」のリンクを足す
- **W5**: 項目の差分は既存の `Opt::TemplateDiff` を使う。パスカードの差分は新規で、キーは
  `identity.path`（スキーマ v1.2）。比べるのは `semantics` のラベルと説明、`binding` のコード束縛。
  スキーマは変えない（読むだけ）
- **W6**: FSH は `rake fsh:export` の出力で、画面には出していない。W6 では FHIR プロファイル（JSON）へのリンクを移す。
  FSH を画面に出すかどうかは 4 節の問い

## 3. 新しい URL（外から見える契約）

| URL | 中身 |
|---|---|
| `GET /templates/:template_id` | 有効な版の詳細 |
| `GET /templates/:template_id/versions/:version` | その版の詳細（置き換えられた版も） |
| `GET /templates/:template_id/diff?from=<版>&to=<版>` | 2 つの版の差分 |

既存の URL は変えない。

## 4. 人間に尋ねる点（答えを待たずに、案のとおり進める）

1. 左ナビの項目は、いまの 4 つのままでよいか。M3 の後半で「患者」が入る位置は、テンプレートの上を想定している
2. W6: カルテ記録の画面の「FHIR プロファイル」のリンクは、テンプレートの詳細へのリンクに置き換える（案）。
   両方に残すほうがよければ、そうする
3. W6: FSH を画面に出すか（案: 出さない。`sushi` が要るので、画面からは作らない）

## 5. 順序

W1 → W2 → W3 → W4 → W5 → W6。W1 と W2 は layout を触る。layout は「引く側」のレーンも触るファイルなので、
W1 と W2 は続けて出し、早くマージする。0.9.0 が公開されたら、列の途中でも M2 の F に移る（R-20261124-10）。

## 6. 範囲の外

- 患者（EHR）、カルテ記録の一覧・版・削除（作業列 7）
- テンプレートの削除と、版の巻き戻し
- デザインの作り込み（配色、アイコン）。W1 は配置と、いまの画面の印までにする

## 7. 追記（2026-11-25）: 患者と EHR、カルテ記録の管理（R-20261124-20 作業列 4）

裁定 ID: R-20261124-20 作業列 4（R-20261125-1 で進行の許可）。状態: **案（push して、そのまま進む。R-20261124-8）**。
基準点: anlage main `20312e1`（openehr 2.5.0、openehr-rails 0.9.0）。「実測」は anlage のツリーと、インストール済みの openehr-rails 0.9.0 を読んだ結果。

### 7.1 いまの状態（実測）

- EHR は 1 つも作られていない。保存は `OpenehrRails::Rm::CompositionCommitter.commit(committable_hash, uid: uid, owner: nil)`
  （`app/lib/opt/rm_composition_committer.rb:28`）で、`ehr:` を渡さない。RM の composition の `ehr_id` は NULL
- gem の EHR は `OpenehrRails::Rm::Ehr`（`openehr_ehrs`。列は ehr_id・subject_id・subject_namespace など。
  openehr-rails 0.9.0 `lib/openehr_rails/rm/ehr.rb:7`）。作り方は gem の REST と同じく
  `Ehr.create!(ehr_id: SecureRandom.uuid, subject_id:, subject_namespace:)`（`app/controllers/openehr_rails/openehr_api/ehrs_controller.rb:142`）。
  患者マスタ（PARTY）のモデルは gem に無い。患者を表すのは EHR の subject（PARTY_SELF の external_ref）だけ
- 版: committer は同じ uid で commit すると前の head の `latest_version` を false にして、`Rm::Version` を 1 つ足す
  （`composition_committer.rb:191-208`）。版の id は `<uid>::<system_id>::<N>`（`rm/version.rb:140`）
- 削除: gem の REST の DELETE は、head を同じ uid で commit し直して、その版の `lifecycle_state_code` を
  `LIFECYCLE_DELETED`（523）にする論理削除（`openehr_api/compositions_controller.rb:57-65`）。
  AQL（`Aql::Executor` の既定 `Composition.latest`）は、削除の版を除かない
- anlage の `compositions` テーブル（原本の表示用、非権威）は RM と uid の文字列でだけ対応する。ehr の列は無い

### 7.2 方針

- **migration を足さない**。EHR との結び付きと版・削除の状態は、RM の側（`openehr_rm_compositions.ehr_id`、
  `openehr_rm_versions`）を権威として読む。anlage の `compositions` は、版ごとに 1 行の原本（同じ uid の行が版の数だけ並ぶ）
- 患者 = EHR 1 つ。画面で持つのは患者 ID（subject_id）と名前空間（subject_namespace、既定は `anlage`）だけ。
  氏名などの個人情報の列は作らない（PARTY のモデルが gem に無い。デモのデータに個人情報を持たせない）
- 「いまの患者」はセッションに持つ（`session[:ehr_id]`）。選んでいれば、保存した記録をその EHR に結び付ける。
  **選んでいなければ、これまでどおり EHR に結び付けずに保存する**（下の 4 の問い。デモの操作列と既存の spec を変えない）
- 削除は利用者の操作（画面のボタン）として、gem の REST と同じ論理削除にする。開発機のデータは消さない。
  画面（一覧・患者の記録）からは削除済みを外す。AQL からは外れない（gem の既定の scope。`docs/upstream-candidates.md` に足す）

### 7.3 項目（1 Issue = 1 PR、Red から）

| # | 項目 | Red から始める spec の見出し | 触るファイル |
|---|---|---|---|
| P1 | 患者（EHR）の一覧と作成 | 「患者 ID を入れて作ると、EHR が 1 つでき、一覧に出る」「同じ患者 ID（同じ名前空間）は 2 つ作れない（422）」「患者 ID が空なら 422」 | `config/routes.rb`（`resources :patients, only: %i[index create show]`）、`app/controllers/patients_controller.rb`、`app/views/patients/`、`_nav.html.erb` |
| P2 | 患者を選ぶ | 「患者を選ぶと、ナビにいまの患者が出る」「選択を外せる」「無い EHR は選べない（404）」 | `POST /patients/:id/select`・`DELETE /patients/selection`、`ApplicationController#current_ehr` |
| P3 | 記録を EHR に結び付ける | 「患者を選んで帳票を保存すると、RM の composition の ehr がその EHR になる」「患者の画面に、その患者の記録が新しい順に出る」「選んでいなければ、これまでどおり結び付けない」「AQL の `FROM EHR e[ehr_id/value='…']` で、その患者の記録だけが引ける」 | `app/lib/opt/rm_composition_committer.rb`（`ehr:` を渡す）、`compositions_controller.rb`、`patients/show` |
| P4 | 記録の版（修正） | 「記録の画面から修正すると、同じ uid の 2 版めができ、一覧には新しい版だけが出る」「記録の画面に版の履歴（版・日時）が出る」「修正の帳票には前の版の値が入っている」 | `GET /compositions/:id/edit`・`PATCH /compositions/:id`、`Opt::CompositionReader`（読み戻せない形は修正を出さない）、`compositions/show` |
| P5 | 記録の削除 | 「削除すると、削除の版ができ（lifecycle 523）、一覧と患者の画面から消える」「削除済みの記録の画面は『削除済み』と出し、修正・削除は出さない」 | `DELETE /compositions/:id`、`compositions/index`・`show` |

補足:

- **P1 の URL の `:id`** は ehr_id（gem の engine の `ehrs/:id` と同じ）。engine の EHR の画面（`/openehr/ehrs`）は変えない（gem）
- **P3 の AQL の spec** は、引く側のファイル（`app/lib/query_builder/`）を触らない。engine の `Aql::Executor` を直接呼ぶ
- **P4 の修正の帳票**は、`Opt::CompositionReader` で読み戻した値を入れる。読み戻せない形（Issue #30 の残り・#82）がある
  テンプレートは、修正のリンクを出さない（黙って値を落とさない）。版の 2 つめの原本は、`compositions` に新しい行として足す
- **P5** は gem の REST の DELETE と同じ手順（同じ uid で commit し、その版を 523 にする）を anlage の側で行う。
  gem の公開されたモデル（`Rm::Composition`・`Rm::Version`）だけを使う
- 文言は `docs/demo/ui-vocabulary.md` に足す（「患者」「患者 ID」「いまの患者」「修正」「削除」「版の履歴」「削除済み」）。
  ナビの「患者」はテンプレートの上（4 節の 1。R-20261124-20 で案のとおり）

### 7.4 新しい URL（外から見える契約）

| URL | 中身 |
|---|---|
| `GET /patients`・`POST /patients` | 患者（EHR）の一覧と作成 |
| `GET /patients/:id` | 患者の記録（:id は ehr_id） |
| `POST /patients/:id/select`・`DELETE /patients/selection` | いまの患者の選択と解除 |
| `GET /compositions/:id/edit`・`PATCH /compositions/:id`・`DELETE /compositions/:id` | 記録の修正と削除 |

既存の URL は変えない。

### 7.5 人間に尋ねる点（答えを待たずに、案のとおり進める）

4. 患者を選ばずに保存したとき: 案は「これまでどおり、EHR に結び付けずに保存する」。openEHR では記録は必ず EHR に属するので、
   「患者を選ばないと保存できない」にする選択もある（デモの操作列と、実ブラウザの spec 2 つが変わる）
5. 患者の表示は患者 ID だけ（氏名を持たない）でよいか
6. 削除が AQL から外れないこと（gem の既定）を、既知の制限として v0.2.0 の一覧に載せる（案）。外すには gem の変更が要る

### 7.6 順序と範囲の外

- P1 → P2 → P3 → P4 → P5。P3 のあと、作業列 5（v0.2.0 の準備）と並べて進めてよい
- 範囲の外: 患者の氏名・生年月日など（PARTY）、EHR の削除、記録の版の巻き戻し、削除の取り消し、AQL の版の指定（VERSION）
