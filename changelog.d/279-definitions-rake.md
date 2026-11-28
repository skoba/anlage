- Add: 定義の組の rake: `bin/rails definitions:register DIR=`、`definitions:activate BUNDLE= VERSION=`、`definitions:restore BUNDLE= VERSION=`、`definitions:list`（Refs #279、Refs R-20261128-7。D-3b）。利用者に見える変更: あり（運用者向けの rake）。
  認証が無いあいだ、定義の組の書き込みは rake だけ（画面からはできない）。戻すと、前の版の中身が新しい版として足される（履歴は消えない）
