# M3（ワークベンチ）の進行ログ

計画: `docs/design/m3-plan.md`。作業列: R-20261124-10（anlage、書く側）の 5。
進め方: R-20261124-8（`CLAUDE.md`「全開の進め方」）。

## R1 W1・W2（`skoba/anlage#95`）: 統合レイアウト（2026-11-24）

ブランチ `feat/95-unified-layout`。基準点は main `7d466ad`。

### 自己承認した判断

1. **W1 と W2 を 1 つの Issue、1 つの PR にした**（計画書は 2 項目に分けていた）。
   どちらも layout を触り、ナビの partial を共有する。分けると W1 のあいだ AQL 照会だけ古い配置になる
2. **engine の画面は、engine の layout を anlage の側の同じパスで上書きして入れた**
   （`app/views/layouts/openehr_rails/application.html.erb`）。gem は変えていない。
   - 根拠: engine のコントローラは `layout 'openehr_rails/application'`
     （openehr-rails 0.8.0 `app/controllers/openehr_rails/application_controller.rb:5`）。
     Rails はアプリの `app/views` を先に探す。Red → Green で、`GET /openehr/query` に anlage のナビが出ることを確かめた
   - engine の画面が前提にするスタイル（表、通知）は、gem 0.8.0 の layout から `.openehr-engine` の下に写した。
     **gem の layout が変わったら見直す**（0.9.0 の受け入れ〔M2 の F〕のときに確かめる項目に足す）
   - engine の画面の本文にある「Templates · Patients」のリンク（gem の view の中）は残る。
     view までは上書きしていない
3. **既存の spec 3 件を、新しい構造に合わせて直した**（期待する文言は変えていない）:
   `spec/requests/ui_vocabulary_spec.rb` の見出しのセレクタ 2 箇所（`body > h1` → `main#workspace > h1`）、
   `spec/system/demo_save_next_actions_spec.rb` の「ナビは 1 行」を「ナビは左に縦 1 列」に
4. **`docs/demo/ui-vocabulary.md` の「共通ナビ」の行に、置き場所と印を書き足した**（文言は変えていない。同じコミット）

### Red（実装の前、5 失敗）

```
1) デモ動線: 共通ナビと保存後の次アクション 統合レイアウト（#95） ナビは作業面（main#workspace）の外にあり、作業面に画面の中身が入る
     expected: ["カルテ記録一覧"]
          got: []
2) … いまの画面の項目に印が付く（帳票はテンプレート、カルテ記録は一覧の項目）
     / の印
3) … AQL 照会（engine の画面）にも同じ 4 リンクが出て、AQL 照会に印が付く
     expected: [["テンプレート", "/templates"], ["カルテ記録一覧", "/compositions"], ["パスカード検索", "/pathcards/search"], ["AQL 照会", "/openehr/query"]]
          got: []
4) 統合レイアウト（実ブラウザ） ナビが左、作業面が右に並び、横スクロールが出ない（テンプレート・カルテ記録一覧・パスカード検索・AQL 照会）
     javascript error: Cannot read properties of null (reading 'getBoundingClientRect')
5) 統合レイアウト（実ブラウザ） AQL 照会からナビでテンプレートに戻れる
     Capybara::ElementNotFound: Unable to find css "nav#app_nav"
```

### Green

- 開発機の全 suite: 267 例 0 失敗、3 pending（基準点は openehr 2.4.3。pending は `#23` (4) の 3 件）。rubocop 違反なし
- 実ブラウザ（Chrome 158、1280×720）で、テンプレート・帳票・パスカード検索・AQL 照会の 4 画面を撮って目で確かめた。
  ナビは左、作業面は右、横スクロールなし

### 開発機の環境について

- 開発機には日本語のフォントが 1 つも入っていない（`fc-list :lang=ja` が 0 件）。headless Chrome の
  スクリーンショットでは、日本語が豆腐（□）になる。spec は文字列で照合するので合否には関わらない。
  見た目を確かめるには、フォントの入った環境（壇上の機械）で見る必要がある

### 引く側のレーンへ

- layout と `application.css` を変えた。パスカード検索の画面は `main#workspace` の中に入る。
  引く側の PR で `body > …` のセレクタを使っていれば、rebase のときに直す

## R2 W3・W4（`skoba/anlage#98`）: テンプレートの詳細画面と版の履歴（2026-11-24）

ブランチ `feat/98-template-detail`。基準点は main `0d14285`。

### 自己承認した判断

1. **W3 と W4 を 1 つの Issue、1 つの PR にした**。版の履歴は詳細画面の一部で、置き換えられた版の詳細も同じ action と view を使う
2. **新しい URL は計画書 3 節のとおり 2 つ**（`/templates/:template_id`、`/templates/:template_id/versions/:version`）。
   `:template_id` の制約は `forms/:template_id` と同じ（`/[^\/]+/`、`format: false`。template_id は `patient_blood_pressure.v1` のように点を含む）
3. **版の並びは `Gem::Version` で比べる**（`1.0.10` が `1.0.9` より新しくなる。文字列の比較だと逆になる）
4. **fixture**: 2 つめの版は、実物の OPT のラベルを 1 つ置き換えたもの（`spec/requests/templates_spec.rb` の
   既存のやり方と同じ、実物からの導出）。取り込みの経路（`POST /templates`）で登録している
5. **文言を `docs/demo/ui-vocabulary.md` に 1 行足した**（同じコミット）

### Red（実装の前、8 例 6 失敗。404 の 2 例は実装の前から緑）

```
1) テンプレートの詳細と版の履歴 一覧 カードから詳細に行ける
     expected [["帳票に入力", "/forms/patient_blood_pressure.v1"]] to include ["詳細", "/templates/patient_blood_pressure.v1"]
2) … GET /templates/:template_id（有効な版の詳細） 見出しと、template_id・登録版・帳票の可否・項目数・パスカードの枚数が出る
     expected the response to have status code :ok (200) but it was :not_found (404)
3) … 詳細から帳票に入力できる
     expected [] to include ["帳票に入力", "/forms/patient_blood_pressure.v1"]
4) … 版の履歴に、同じ template_id の版が新しい順に並び、有効な版に印が付く
     expected: "版の履歴"
          got: ""
5) … GET /templates/:template_id/versions/:version（置き換えられた版の詳細） その版の中身が出て、…
     expected the response to have status code :ok (200) but it was :not_found (404)
6) … 閲覧専用のテンプレート（jp_referral） 帳票の行に、閲覧専用であることと理由が出る
     expected nil to start with "閲覧専用（"
```

### Green

- 開発機の全 suite: 275 例 0 失敗、3 pending。rubocop 違反なし

## R3 W5（`skoba/anlage#100`）: 版差分の画面（2026-11-24）

ブランチ `feat/100-version-diff`。基準点は main `2d9c5f5` のあと（openehr 2.5.0 の PR #92 がマージ済みの main）。

### 自己承認した判断

1. **パスカードの差分は新しいクラス `Opt::PathcardDiff` にした**。キーは `identity.path`（`Opt::TemplateDiff` が
   field の path をキーにするのと同じ考え方）。比べる観点は 6 つ（ラベル、説明、祖先の名前、型、制約、コード束縛）。
   ラベルなどは文言（text）だけを比べ、未翻訳の判定などの付随情報は比べない。スキーマ v1.2 は読むだけ
2. **項目の差分は、既存の `Opt::TemplateDiff` をそのまま使った**。取り込みの確認画面（`preview.html.erb`）の
   差分の表示と文言は変えていない
3. **版の履歴の各行に「前の版との差分」を足した**。そのため `#98` の spec（版の履歴の行の文言とリンク）の期待値を 1 箇所直した
4. **文言を `docs/demo/ui-vocabulary.md` に 1 行足した**（同じコミット）

### Red

`Opt::PathcardDiff` の単体（実装の前）:

```
An error occurred while loading ./spec/lib/opt/pathcard_diff_spec.rb.
NameError: uninitialized constant Opt::PathcardDiff
```

画面（実装の前、4 例 3 失敗。「無い版は 404」は実装の前から緑）:

```
1) テンプレートの版差分 版の履歴から、前の版との差分に行ける
     expected [["登録版 v1.0.0", "/templates/patient_blood_pressure.v1/versions/1.0.0"]] to include ["前の版との差分", "/templates/patient_blood_pressure.v1/diff?from=1.0.0&to=1.0.1"]
2) … 2 つの版を指定すると、変更された項目と、パスカードの差分（ラベルの前後）が出る
     expected the response to have status code :ok (200) but it was :not_found (404)
3) … 同じ版どうしなら、差分が無い旨が出る
     expected the response to have status code :ok (200) but it was :not_found (404)
```

途中で spec の側の誤りを 1 つ直した: 「片方にしか無いカード」の fixture の選び方が緩く
（`/items[at0004]/value` で終わるカードが 2 枚ある。実測）、ラベルが「Systolic」のカードを選ぶ形にした。

### Green

- 開発機の全 suite: 284 例 0 失敗、2 pending（openehr 2.5.0。pending は手写像の元が未供給の 2 件）
- rubocop 違反なし、brakeman の警告 0
- 実ブラウザ（1280×720）で、版の差分の画面に横スクロールが出ないことを spec に足した

## R4 W6（`skoba/anlage#102`）: FHIR プロファイルのリンクをテンプレートの詳細に移す（2026-11-24）

ブランチ `feat/102-fhir-links-on-template`。基準点は main `4633cae`。

### 自己承認した判断（計画書 4 節の問い 2・3 は、答えを待たずに案のとおり進めた）

1. **カルテ記録の画面の「FHIR プロファイル」は、「テンプレートの詳細」へのリンクに置き換えた**（問い 2 の案）。
   次アクションは 4 つのまま。両方に残すほうがよければ、revert ではなく 1 行足すだけで戻せる
2. **FSH は画面に出していない**（問い 3 の案）
3. **テンプレートの詳細には、すべてのプロファイルを並べた**。これまでのリンクは先頭の 1 つだけだった
   （patient_blood_pressure.v1 は 2 本ある。`spec/models/template_spec.rb` の実測）
4. **プロファイルの欄は、有効な版にだけ出す**。facade は有効なテンプレートのプロファイルだけを返すので、
   置き換えられた版で出すとリンクが 404 になる
5. **壇上の動線の spec を 2 つ直した**（`spec/requests/demo_navigation_spec.rb`、`spec/system/demo_save_next_actions_spec.rb`）。
   台本（次アクションの 4 つめ）が変わるので、`docs/demo/ui-vocabulary.md` も同じコミットで直した

### Red（実装の前、3 失敗）

```
1) デモ動線: 共通ナビと保存後の次アクション 保存後のカルテ記録画面 次アクション 4 つ（同じ帳票にもう 1 件／カルテ記録一覧／AQL 照会／テンプレートの詳細）を出す
     （4 つめが [ "FHIR プロファイル", "/fhir/r5/StructureDefinition/openehr-observation-heart-rate-pulse-v1" ] のまま）
2) テンプレートの詳細と版の履歴 GET /templates/:template_id（有効な版の詳細） FHIR プロファイルの欄に、すべてのプロファイルへのリンクが出る
     expected: "FHIR プロファイル"
          got: ""
3) デモ動線: 保存後の次アクション（実ブラウザ） CardiologyEncounter を保存すると flash と次アクション 4 つが出て、…
     expected to find link "テンプレートの詳細" with href "/templates/CardiologyEncounter" … but there were no matches
```

### Green

- 開発機の全 suite: 285 例 0 失敗、2 pending。rubocop 違反なし

### M3 の先行分の残り

- W1〜W6 はこれで出そろった。作業列 7（患者と EHR、カルテ記録）は M2 の出口のあと

## R5 P1（`skoba/anlage#130`）: 患者（EHR）の一覧と作成（2026-11-25）

計画書 `docs/design/m3-plan.md` 7 節（PR #129 → main `0cde02a`）。R-20261124-20 作業列 4。

### 実測（gem の API）

- `OpenehrRails::Rm::Ehr`（openehr-rails 0.9.0 `lib/openehr_rails/rm/ehr.rb:7`）: `validates :ehr_id, presence: true, uniqueness: true`、
  `time_created`・`system_id` は before_validation で入る
- 作り方は gem の REST と同じ: `Ehr.create!(ehr_attributes.merge(ehr_id: SecureRandom.uuid))`（`app/controllers/openehr_rails/openehr_api/ehrs_controller.rb:142`）
- gem には患者 ID の一意の制約が無い。重複は anlage の側で（名前空間ごとに）確かめる

### 判断（自己承認、計画書の範囲内）

- 一覧に出すのは subject_id のある EHR だけ（gem の REST で subject なしに作られた EHR は出さない）
- 名前空間は固定の `anlage`（入力欄を出さない）

### Red

```
$ bundle exec rspec spec/requests/patients_spec.rb spec/requests/demo_navigation_spec.rb spec/requests/queries_spec.rb
      1      Failure/Error:
      1      Failure/Error: expect(current_items).to eq(expected), "#{path} の印"
      2      Failure/Error: expect(links_in("nav#app_nav")).to eq(NAV_LINKS)
      1      Failure/Error: expect(links_in("nav#app_nav")).to eq(NAV_LINKS), "#{path} のナビ"
      1      Failure/Error: expect(nav.map(&:first)).to eq(%w[患者 テンプレート カルテ記録一覧 パスカード検索 クエリビルダー] + [ "AQL 照会" ])
      1      Failure/Error: expect(response).to have_http_status(:ok)
      2      Failure/Error: expect(response).to have_http_status(:unprocessable_content)
      1 24 examples, 9 failures
```

（ナビの pin は語彙表の写しなので、語彙表と同じコミットで 6 項目に追随させた。`spec/requests/queries_spec.rb` は引く側のファイルだが、語彙の追随だけ）

### Green

全 suite（開発機）: `454 examples, 0 failures, 2 pending`
