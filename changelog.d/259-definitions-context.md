- Add: `bin/rails definitions:context [FORMAT=json]`（Refs #259、Refs R-20261127-21。D-2）。利用者に見える変更: あり（開発者向けの rake のタスク）。
  生成 AI が定義を書くための材料（登録済みのテンプレートの項目の名前・見出し・型・単位、部品、検査の一覧、JSON Schema、例 `docs/definitions/example/`）を出す。
  外の LLM に送られる前提で作り、記録・患者と EHR の ID・bindings・用語のコード・値集合・OPT のファイルは入れない
