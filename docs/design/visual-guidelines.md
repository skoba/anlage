# 見た目の基準

裁定 ID: R-20261127-13（承認済みの `docs/design/u1-patient-chart-plan.md` 3 節）。Issue skoba/anlage#218（U1-0）。
シンプルで、見た目も整える（小林）。外部の CSS の枠組みは足さない。統括のモックアップが届いたら、この表を直す。

## ファイル

| ファイル | 中身 |
|---|---|
| `app/assets/stylesheets/tokens.css` | 色・余白・角丸・書体の変数（`:root`）。色を決めるのはここだけ |
| `app/assets/stylesheets/components.css` | 部品（表 `table.data-table`、カード `.card`、ボタン `.button`・`.button.primary`）。クラスを付けたものだけに効く |
| `app/assets/stylesheets/application.css` | 画面ごとの配置（ナビ、作業面、取り込み、帳票の入れ子、クエリビルダー、engine の画面） |

`stylesheet_link_tag :app` が、このディレクトリのファイルをすべて読む。変数は読む順によらず効く。

## 基準

| 項目 | 基準 | 変数 |
|---|---|---|
| 色 | 本文 `#222`、控えめな文字 `#6b7280`、罫線 `#ccc`、地 `#f3f4f6`、アクセント `#2563eb`、危険 `#b91c1c`、注意 `#b45309`。明るい配色だけ | `--color-text`・`--color-muted`・`--color-border`・`--color-surface`・`--color-accent`・`--color-danger`・`--color-warning` |
| 注記の地 | 注意・成功・誤りの注記の地は、上の色の薄い色（`#fef3c7` など）を、その注記の規則の中に直に書く（変数にしない。使う場所が 1 つずつのため） | — |
| 余白 | 0.25rem 刻み。部品の間は 1.5rem、部品の中は 0.75rem〜1rem | `--space-1`〜`--space-6` |
| 文字 | 本文 1rem、h1 1.5rem、h2 1.25rem、h3 1rem（太字）。行間 1.5。数値の表は等幅数字（`tabular-nums`） | `--font-body`・`--font-mono` |
| 表 | 罫線は横線だけ、見出しの行は地の色、数値は右寄せ（`td.number`） | `table.data-table` |
| カード | 部品 1 つを 1 枚に。枠 1px、角丸 6px、余白 1rem。見出しはカードの中の h2 | `.card`、`--radius` |
| ボタン | 主ボタン（保存・実行）は塗り、ほかは枠だけ。高さ 2.25rem | `.button`、`.button.primary` |
| 帳票の入力欄 | いまの `fieldset.root-group`（ラベルの下に入力欄）。エラーと必須の凡例の CSS は good first issue #203 で、この基準の変数を使って書く | — |

## 守ること

- 新しい色を直に書かない。足すなら、この表と `tokens.css` に足す
- 1280×720 で横スクロールを出さない（`spec/system/unified_layout_spec.rb`）
- 見た目そのものは spec で固定しない。固定するのは、変数が定義されていることと、主な部品が変数で描かれていること
  （`spec/system/visual_tokens_spec.rb`）
