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

## R4 サイクル 3・4: 節パスの実在（2026-11-24）

- Red: 存在しない節で findings が空／`c/name/value` の info が出ない（7 examples, 2〜3 failures）
- Green: `app/lib/query_builder/corpus.rb`（active のカードを archetype_id ごとに「ルートから下の節パス」で索引。判断 D3）。
  リンタは述語を持つ最後の PathPart までを節として照合し、無ければ error（path）に同じアーキタイプの候補を添える。
  アーキタイプの述語が無い変数（c・e）は info、索引に無いアーキタイプは error。SECTION 配下（jp_referral の problem_diagnosis）も同じ規則で見つかる
- 直し: `ObjectPath#to_s` は述語をオブジェクトのまま埋めるので、AQL 片の表示は自前で組んだ。7 examples, 0 failures

## R5 サイクル 5: 終端ホップ（2026-11-24）

- Red: DV_TEXT への `value/magnitude`、`value/defining_code/code_string` で findings が空（10 examples, 2 failures）
- Green: 節のあとのホップ列を見る。`[]`・`value`・`name/value` は許す。`value/x` は x がエンジンの終端ホップ（magnitude／name／value）に
  あること（無ければ error に上流候補の項番: defining_code→10 項、time→11 項、archetype_details→25 項）、2 段より深くないこと、
  カードの rm_type に x があること（DV_QUANTITY／DV_COUNT は magnitude、DV_TEXT 系は value）
- 訂正: 設計書 2.1 で DV_QUANTITY に `value/units` を許すと書いたが、`ALLOWED_TERMINAL_HOPS` に units は無く実行時に落ちる（`path_evaluator.rb:23`）。
  リンタは units も error にする。設計書は実装の PR で直す。10 examples, 0 failures

## R6 サイクル 6: 型（2026-11-24）

- Red: `magnitude > "110"`、DV_DATE_TIME に `"2026年1月1日"`、DV_TEXT に `= 3` で findings が空（13 examples, 3 failures）
- Green: 節とホップが通った IdentifiedPath を `@resolved` に覚え、WHERE の `Comparison` ごとにリテラルの型を見る。
  magnitude は数値、value は文字列、DV_DATE_TIME／DV_DATE／DV_TIME は ISO 8601 で読めること（`Time.iso8601` → `Date.iso8601`）。13 examples, 0 failures

## R7 サイクル 7: 値集合（2026-11-24）

- Red: at0073 に `MATCHES {"疑い", "疑惑"}` で findings が空、at0002（外部値集合）で info が出ない（16 examples, 2 failures）
- Green: WHERE の `=` と `MATCHES`（リテラルの値リスト）を集め、DV_CODED_TEXT の `value/value` なら `constraints.value.code_list[].label` と照合。
  無い値は error（value_set）に許される値を添える。code_list が空（外部値集合）は info（検査できない。コンテンツ防火壁により展開しない）。16 examples, 0 failures

## R8 サイクル 8・9: name 述語と永続的な未対応（2026-11-24）

- Red: name 述語で warning が出ない、`VERSIONED_COMPOSITION` で `unsupported` が出ない（18 examples, 2 failures）
- Green: パスの述語に value（名前）があれば warning（name_predicate、24 項・openehr-ruby#60）。`QueryValidator` の `UnsupportedFeature` は error（unsupported）に写す
- 実測: `VERSION v`・`LENGTH(...)` は構文（`InvalidQuery`: expected IDENTIFIER）で落ち、`QueryValidator` の未対応に届くのは `VERSIONED_COMPOSITION` と
  `MATCHES {TERMINOLOGY(...)}`。spec は前者で固定。18 examples, 0 failures
- 設計書 3 節のリンタの TODO 9 項目はすべて green。次はビルダー（2.2）
