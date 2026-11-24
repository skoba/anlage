# S2（クエリビルダーとリンタ）の進行ログ

裁定: R-20261124-11（作業列 4・5）、R-20261124-8。設計: `docs/design/s2-query-builder-plan.md`。
レーン: anlage（引く側）。worktree `/home/skoba/src/anlage-worktrees/s2-query-builder`。

## R1 着手と探索（2026-11-24）

- 基準点: main `c09d72f`（書く側の PR #83 まで）。S1 の枠組み（PR #84）は未マージなので、S2 の評価への接続は #84 のあと
- 実測（設計書 1 節）: `QueryValidator`（openehr-rails 0.8.0）は構文と永続未対応だけを見る。存在しないノードは 0 行で誤りが見えない。
  `OpenEHR::AQL::Model` は freeze された値オブジェクト（`identified_path.rb`・`object_path.rb`・`predicate.rb`・`where_clause.rb`）。
  カードの `constraints.value.code_list` は at0073 で `[{code: at0074, label: 疑い}, …]`、at0002（外部値集合）は空
- 自己承認した判断は設計書 4 節 D1〜D5

## R2 サイクル 1: 構文（2026-11-24）

- Red: `NameError: uninitialized constant QueryBuilder`
- Green: `app/lib/query_builder/finding.rb`、`app/lib/query_builder/linter.rb`。`QueryValidator.validate!` の `InvalidQuery` を error（syntax）に写す。1 example, 0 failures

## R3 サイクル 2: 変数（2026-11-24）

- Red: findings が空（2 examples, 1 failure）
- Green: FROM の containment を歩いて `Binding`（variable・class_name・archetype_id）を集め、SELECT／WHERE の `IdentifiedPath` を出現順に集めて照合。
  未宣言は error（variable）。2 examples, 0 failures
