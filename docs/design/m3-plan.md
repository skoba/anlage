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
