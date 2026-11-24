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
