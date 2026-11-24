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
