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

## R9 ビルダーの本体と画面の着手（裁定 R-20261124-21、作業列 1・2）（2026-11-24）

- 基準点: main `66f3a85`（openehr 2.5.0、openehr-rails 0.9.0）。worktree `/home/skoba/src/anlage-worktrees/s2-builder`、ブランチ `feat/s2-builder`
- 設計: 設計書 6 節（`4604fa9`）。自己承認した判断は 6.6 の G1〜G5（SECTION を FROM に書かない、ENTRY は 1 クエリに 1 つ、
  コード値は `defining_code/code_string`、画面の状態は URL だけ、画面は AQL の文字列を受け取らない）
- 実測（越境は読み取りだけ。対象は `Gemfile.lock` が指す openehr 2.5.0 の gem）:
  - `lib/openehr/aql/engine/path_evaluator.rb:23` `ALLOWED_TERMINAL_HOPS = %w[code_string defining_code magnitude name time value]`
  - `lib/openehr/aql/engine/predicate_evaluator.rb:17-21` LIKE は glob（`?`・`*`、値の全体に一致）
  - `lib/openehr/aql/lexer.rb:74-78` 文字列リテラルのエスケープ
  - `path_evaluator.rb:93-96` 1 つの節が複数に当たると `fan-out SELECT paths are not yet supported`
- 書く側との重なり: `status/anlage-write.md` を読み、開いている PR #113 の変更ファイルに routes・レイアウト・語彙表が無いことを確かめた

## R10 サイクル: リンタの追随（`434937a`）

- Red: `linter_spec` 22 examples, 5 failures（code_string が error（終端ホップ）のまま、コードの値集合の指摘が出ない、型の指摘が出ない）
- Green: `ENGINE_HOPS` を 2.5.0 の実物に、`CODE_HOPS`（`value/defining_code/code_string`、DV_CODED_TEXT だけ）、値集合はコードなら `code_list[].code` と照合し
  許されるコードを表示つきで添える。22 examples, 0 failures
- 変えたもの: 「defining_code は error（上流候補 10 項）」の例を、「DV_CODED_TEXT なら通る／DV_TEXT と途中で切れた形は error」に置き換えた

## R11 サイクル: ビルダー（`58c8c31`）と実行器（`509e930`）

- Red: `uninitialized constant QueryBuilder::Builder`（0 examples, 1 error）
- Green: `app/lib/query_builder/builder.rb`、`Corpus#cards`・`Corpus.ref`・`Corpus#find`。`builder_spec` 11 examples を含め 33 examples, 0 failures
  - 組んだ AQL は、評価 v2 の a001〜a004 の参照 AQL と同じ形（AS の別名だけ無い）
- Red: `uninitialized constant QueryBuilder::Runner`
- Green: `app/lib/query_builder/runner.rb`。demo_initial の上で a001〜a005 と同じ選択を組んで実行し、ゴールドの期待行と一致（`AqlScorer` で match）。4 examples, 0 failures

## R12 サイクル: 画面（`75407cc`）

- Red: `spec/requests/queries_spec.rb` 12 examples, 11 failures（route が無い）
- Green: `GET /queries/new`（`QueriesController#new`、`app/views/queries/new.html.erb`）。12 examples, 0 failures
- ナビ: Red は `demo_navigation_spec` 3 failures（リンクが 5 つになった）。語彙表（`docs/demo/ui-vocabulary.md`）とナビの spec を同じコミットで更新
- 実ブラウザ: `spec/system/demo_query_builder_spec.rb`（`js: true`、3 例: 数値・値集合・組めない値）。横スクロールが出ないことも見る
- 画面に入れていないもの: 文字列の「いずれかに一致」（`MATCHES` の複数値。ビルダーの本体にはある。a003 の形は画面からは「含む」で近い問いになる）、OR、複数の ENTRY

## R13 全 suite で見つけた spec の定数の衝突（`d64b9ae`）

- 全 suite: 399 examples, 1 failure（`spec/lib/evaluation/runner_spec.rb:73` が `:unexecutable`。単独では通る）
- 原因（実測）: `RSpec.describe` の中の定数はトップレベルに出る。新しい `queries_spec.rb` の `SYSTOLIC`（カードの参照）が、
  `evaluation/runner_spec.rb` の `SYSTOLIC`（AQL）を上書きした
- 直し: 新しい spec の定数に `QB_` の接頭辞。spec 全体で重複する定数名が無いことを確かめた（`grep` で重複 0）
- 全 suite（worktree、SQLite）: 399 examples, 0 failures, 2 pending。rubocop 146 files, no offenses

