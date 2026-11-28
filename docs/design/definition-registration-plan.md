# 画面の定義の登録と、患者の画面の上書き（D-3・D-4）の計画

裁定 ID: R-20261128-1（「D-3・D-4 の計画とゲート報告」）。Issue: `skoba/anlage#265`。状態: **計画（ゲート報告を出して、回答待ち）**。
実装は回答のあと（migration があるので、必ず止まる 2）。
基準点: anlage main `1c25de1`（openehr 2.9.0、openehr-rails 0.12.0）。親の計画: `docs/design/definition-layer-plan.md`（1 節の組、2.5 節の版と下書き、5 節の段）。

ねらい: 定義の組を置くと、コードを変えずに、患者の画面が変わる（世界公開の条件 4）。D-3（登録）だけでは画面が変わらないので見せられない。
D-4（上書き）と 1 つの計画にする（R-20261128-1）。

## 0. いまの形（実測）

| もの | いまの形 | 出どころ |
|---|---|---|
| 患者の画面 | `PatientsController#show` が `Charts::PatientChart.call(@patient)` を呼び、`patients/_chart` が、プロブレムリスト → 経過 → 検査結果 → 依頼と紹介状 → 記録の一覧の順に出す。部品は U1 の規則（R1〜R4）で、登録済みのテンプレート全体から決まる | `app/controllers/patients_controller.rb`（`show`）、`app/lib/charts/patient_chart.rb`、`app/lib/charts/rules.rb`、`app/views/patients/_chart.html.erb` |
| 定義の組 | ファイルのまま。`Definitions::Linter.call(dir, templates: Template.active)` が、ディレクトリを読んで D1〜D8 を検査する。登録の表は無い | `app/lib/definitions/linter.rb:16` |
| 定義の読み方 | `Definitions::Loader`（`YAML.safe_load`、別名とクラスを許さない、1 ファイル 64 KiB まで） | `app/lib/definitions/loader.rb` |
| テンプレートの版 | `status` は active と superseded。同じ template_id で中身の違う OPT は、パッチの版を上げて足し、前の版を `supersede!` | `app/models/template.rb:6`・`:14`・`:55` |
| テンプレートを消す道 | 画面と API には無い（`config/routes.rb` の templates は index・preview・create・show・diff だけ）。`demo:reset` だけが全部を消す | `config/routes.rb`、`lib/tasks/demo.rake:24-27` |
| 帳票の保存のあと | 記録の画面（`composition_path`）に移る | `app/controllers/compositions_controller.rb:82` |
| 認証 | 無い。両方の環境変数があるときだけ、Basic 認証が全部の画面と API に掛かる | `config/application.rb:35`（`lib/middleware/optional_basic_auth.rb`） |
| 部品の名前 | `problem_list time_series lab_table records form table buttons`。依頼と紹介状は `records` の `from.rm_type: INSTRUCTION` | `app/lib/definitions/schema.rb:6`、`app/lib/definitions/context.rb` |

## 1. 表の形（migration）

**推す案: 1 行 = 1 つの組の 1 つの版**（表 `definition_bundles`）。組・画面・ロジックを別の行にしない。

| カラム | 型 | 中身 |
|---|---|---|
| `bundle_id` | string, null 不可 | 目録の `bundle`（変わらない id） |
| `version` | string, null 不可 | 目録の `version`（ファイルに書いたもの。登録で上げない） |
| `status` | string, null 不可 | `draft`・`active`・`superseded` |
| `files` | json, null 不可 | `{ "bundle.yml" => "<YAML の文字>", "screens/patient_chart.yml" => "…", … }`。読んだ文字をそのまま持つ（読み直すたびに `Definitions::Loader` で読む） |
| `checksum` | string, null 不可 | `files` を path の順に並べた SHA-256 |
| `lint_report` | json | 登録のときの検査の結果（`Definitions::Linter::Report#problems` の `to_h`） |
| `restored_from` | string | 戻したときの、元の版 |
| `registered_by` | string | 登録した手段（`rake` と、環境の利用者名。認証のあとで、利用者に替える） |
| timestamps | | |

- 索引: `(bundle_id, version)` を一意。`bundle_id` ごとに `status = 'active'` は 1 つだけ（SQLite の部分索引 `WHERE status = 'active'`）
- 組を 1 行にする理由
  - 検査（D2 の id の重なり、D5 の遷移先、D6 のたどり着けない画面）は、組を単位にしている（`Definitions::Linter` が組のディレクトリを読む）
  - 動かすときに、画面ごとの版が混ざらない（ある画面だけ新しく、遷移先が古い、が起きない）
  - 差分は組の版どうしで取り、その中を画面・部品・ボタンの id で分ける（親の計画 2.5 節の「id を鍵にした差分」）
- 捨てた案: 画面・ロジックを別の行にして、組の行がそれを指す。版の組み合わせの管理が増え、検査の単位と合わない
- `Definitions::Linter` は、いまディレクトリを読む。表の `files` も読めるように、読み元を「path → 文字」の対応表で受ける形に分ける
  （中の作りの整理。検査の規則と結果は変えない。D-1 の spec を緑のまま直す）

### 1.1 版、下書き、superseded、戻す

| 操作 | 何が起きるか |
|---|---|
| 登録 | 検査にエラーがあれば登録しない（エラーの文を出す。D8 の「案」は警告で、登録してよい）。通れば `draft` で足す。同じ `bundle_id`・`version` で中身が違えば断る（「版を上げてください」）。同じ checksum なら「登録済み」 |
| 試しに表示 | `?preview=<下書きの行の id>` を付けたときだけ、その下書きで画面を出す（親の計画 2.5 節）。画面の上に「下書き <組> <版> を試しに表示している」と出す。印の無い URL は、動いている組のまま |
| 動かす | 下書きを `active` にし、同じ `bundle_id` の前の `active` を `superseded` にする（1 つのトランザクション）。動かす直前に、いまのテンプレートで検査し直す |
| 戻す | 前の版の `files` を写して、**新しい行**として足す（版は、いまの最新の版のパッチを 1 つ上げる。`restored_from` に元の版）。履歴は消さない（親の計画 2.5 節）。版の番号はファイルの中の `version` と食い違うので、写すときに `bundle.yml` の `version` の行を書き換える（書き換えたことを `lint_report` の隣に記す） |
| 消す | 作らない（削除は必ず止まる 3） |

## 2. 動かす組の選び方（運用者の設定）

**推す案: 環境変数 `ANLAGE_DEFINITION_BUNDLE=<bundle_id>`**。その `bundle_id` の `active` の版で動く（R-20261127-21 の回答 1。動かす組はいまは 1 つ）。

- 運用者の設定はこれまでも環境変数（`ANLAGE_BASIC_AUTH_*`、`ANLAGE_ALLOW_DEMO_RESET`）。そろえる
- 変えたら再起動が要る。組の中の版の入れ替え（動かす・戻す）は、表だけで済み、再起動は要らない
- 捨てた案: 「動かす組」を表に持ち、rake で切り替える。再起動は要らないが、運用者の設定が 2 か所（環境変数と表）に分かれる

## 3. 組み込みの定義（既定の画面）と、定義が無い・通らないとき

- U1 の既定の画面を、組み込みの定義として書く: `config/definitions/builtin/`（`bundle.yml` と `screens/patient_chart.yml`）。リポジトリの中のファイルで、表には入れない
- 組み込みの定義の部品は、`from` を書かない。**`from` の無い部品は、U1 の規則（R1〜R4）で、登録済みのテンプレート全体から引く**（いまの画面と同じ）。
  `from` のある部品は、そのテンプレート・field だけを出す
  - これは D-1 の書式の意味を足すこと（いまの検査器は `from` を任意にしているが、`from` の無い部品の意味を決めていない）。
    `rake definitions:context` の部品の説明にも足す
  - 組み込みの定義が、いまの画面と同じ並び（`#problem_list` → `#time_series` → 検査結果 → 依頼と紹介状 → 記録の一覧）と同じ中身を出すことを、spec で pin する
    （D-4 の最初の Red。U1 の request spec と system spec を、組み込みの定義を通しても緑のまま保つ）

| 状態 | 患者の画面に出るもの |
|---|---|
| `ANLAGE_DEFINITION_BUNDLE` が無い | 組み込みの定義（いまの画面）。印は出さない |
| 設定はあるが、その組に `active` の版が無い | 組み込みの定義と、画面の上に「定義の組 <bundle_id> に、動いている版が無い。既定の画面を出している」 |
| `active` の版が、いまのテンプレートで検査に通らない（テンプレートが差し替わったなど） | 組み込みの定義と、画面の上に「定義の組 <bundle_id> <版> が検査に通らない」と、エラーの文（D コード、場所、直し方の候補）。ログにも書く |
| 通る | その組の `start` の画面 |

- 500 にしない。患者の記録が見えなくなるほうが困る（参照実装の判断。決めてほしい点 3）
- 検査し直しは、画面を出すたびには走らせない。鍵（組の行の id と、`Template.active` の id と checksum の並び）で、プロセスの中に覚える。
  テンプレートを登録すると鍵が変わり、次の表示で検査し直す

## 4. 登録の入口と、認証が無いあいだ

**推す案: 書き込み（登録・動かす・戻す）は rake だけ。画面は読むだけ。**

- `bin/rails definitions:register DIR=<組のディレクトリ>` → 下書き
- `bin/rails definitions:activate BUNDLE=<id> VERSION=<版>`、`bin/rails definitions:restore BUNDLE=<id> VERSION=<版>`
- `bin/rails definitions:list`（組・版・状態・検査の結果）
- 画面 `/definitions`（読むだけ）: 組と版の一覧、検査の結果、遷移の図（D-5 の `DefinitionsHelper#transition_diagram`）、版どうしの差分、
  「試しに表示」のリンク（患者を選んでいれば、その患者の画面に `?preview=` を付けたもの）
- 理由
  - 認証が無い。画面から書き込めると、届く人のだれでも、全員の患者の画面を変えられる。rake は、サーバのシェルに入れる運用者だけが使える
  - テンプレートの取り込みは画面から書き込めるが、テンプレートは足すだけで、動いている画面を変えない（新しい版は、帳票に出るだけ）。定義の「動かす」は、全員の画面を変える
  - 参照実装の注意書き（README の「認証が無い」）だけでは足りないと考える。止める設定（画面からの書き込みを環境変数で開ける）は、認証の計画のときに考える（`docs/ideas-2027.md` に書く）
- `?preview=` は読むだけ（下書きを使って画面を出す）なので、だれでも使える。下書きは記録を変えない

## 5. 定義が参照するテンプレートが、差し替わった・消えたとき

- 差し替わった（同じ template_id の新しい版が active になった）: 定義は template_id で引くので、新しい版の field で検査し直す（3 節の鍵）。
  field が消えていれば D3 のエラーになり、組み込みの定義に落ちて、エラーの文を出す（3 節の表）
  - 目録の `templates[].version`（例 `">= 1.0.0"`）は、いまの検査器は形を見るだけ（D-1）。版の条件に合わないときも D3 のエラーにする（D-3 で足す）
- 消えた: 画面と API には消す道が無い（0 節）。`demo:reset` は全部を消して入れ直すので、そのときは定義の組も消す
  （**推す案**。初期データのテンプレートしか残らないので、組の参照が切れる。`demo:reset` の説明にそう書く）
- テンプレートを取り込む画面で、動いている組が通らなくなることを、取り込む前に出すのは、この計画に入れない（`docs/ideas-2027.md`）

## 6. 帳票の保存のあと（`then`）

- ボタンの `open: { form: X, then: … }` は、帳票の URL に **ボタンの印**（`?via=<組の行の id>.<ボタンの id>`）を付ける。
  保存のあと、サーバは、その組の行からボタンを引き直し、`then` の画面に移る（`then: { record: saved }` なら、いまと同じ記録の画面）
- 移る先を URL に書かない（外の URL へ飛ばされる道を作らない）。印が引けないときは、いまと同じ記録の画面に移る
- 画面の部品 `form`（`lab_entry` の例）は、いまの帳票の画面（`forms/show`）をそのまま出す。`table` は D-4 では出さない（「この部品は、まだ画面に出せない」と出す。検査は通す）

## 7. 見せ方（世界公開の条件 4）

- 場面: 患者 DEMO-01 の画面（組み込みの定義）→ `docs/definitions/example/`（`clinic_example`。D-2 の例）を登録 →
  `?preview=` で、同じ患者の画面が、定義どおりの部品の並びになる（コードは変えていない）→ 動かす → 印の無い URL でも変わる →
  戻す → もとに戻る
- 2 つめの組を足す（例: 検査結果だけの画面の組。`spec/fixtures/definitions/` に置き、初期データのテンプレートの field だけを引く）。
  別の組を置くと別の画面が立つことを、system spec と受け入れの台本で見せる
- 受け入れの台本（次の版のもの）に、この場面を足す。録画の台本は、そのあと

## 8. 段と、Red から始める spec の見出し

| 段 | 中身 | Red から始める spec の見出し |
|---|---|---|
| D-3a | 表 `definition_bundles`（migration）とモデル。検査器の読み元を対応表に分ける | 「エラーのある組は登録できず、エラーの文が返る」「同じ組・版で中身の違うものは断る」「動かすと、前の active は superseded になる」「active は組ごとに 1 つ」 |
| D-3b | rake（register・activate・restore・list） | 「戻すと、前の版の中身で新しい版が足され、履歴は消えない」 |
| D-4a | 組み込みの定義と、`from` の無い部品の意味 | 「組み込みの定義で、いまの患者の画面と同じ部品の並びと中身が出る」 |
| D-4b | 動かす組で患者の画面を出す。通らないときは組み込みに落ちる | 「`ANLAGE_DEFINITION_BUNDLE` の組の部品の並びで患者の画面が出る」「テンプレートの field が消えると、既定の画面とエラーの文が出る」 |
| D-4c | `?preview=` と、`via` の印で `then` に進む | 「下書きの定義は `?preview` のときだけ使われ、動いている画面は変わらない」、実ブラウザ:「帳票の保存のあと、`then` の画面に進む」 |
| D-4d | 画面 `/definitions`（読むだけ。一覧、検査の結果、図、差分） | 「画面から登録・動かす道が無い（POST の route が無い）」 |

- 依存（gem）は足さない。migration は 1 つ
- 範囲の外: ロジックの登録（D-6）、流れ（D-7）、計測（D-8）、画面からの書き込み、利用者ごとの組

## 9. 決めてほしい点（ゲート）

ゲート報告（`docs/reports/definitions-log.md` R5）に、推す案と一緒に並べる。

1. 表は、1 行 = 1 つの組の 1 つの版（1 節）でよいか
2. 動かす組は環境変数 `ANLAGE_DEFINITION_BUNDLE` で選ぶ（2 節）でよいか
3. 組が無い・通らないときは、500 にせず、組み込みの定義と、理由の文を出す（3 節）でよいか
4. 組み込みの定義の `from` の無い部品を「U1 の規則で全体から」とする（3 節。D-1 の書式に意味を足す）でよいか
5. 書き込みは rake だけで、画面は読むだけ（4 節）でよいか
6. `demo:reset` で定義の組も消す（5 節）でよいか
7. 保存のあとの `then` は、URL に先を書かず、ボタンの印から引き直す（6 節）でよいか
