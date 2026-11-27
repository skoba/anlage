- Add: `bin/rails definitions:diagram DIR=<組のディレクトリ>`（Refs #260、Refs R-20261127-21。D-5）。利用者に見える変更: あり（開発者向けの rake のタスク）。
  画面の定義から遷移の図（画面・帳票・保存した記録が節、ボタンと保存のあとが辺）を Mermaid のテキストで出す。サーバで描く SVG（`DefinitionsHelper#transition_diagram`）も足した（画面に置くのは組の登録〔D-3〕のあと）
