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

## R14 PR #121 のマージ（2026-11-24）

- main が進み（書く側の #113・#116・#118・#120）、`app/assets/stylesheets/application.css` が競合した。両方とも末尾への追記で、両方を残して解消（`640b6b0`、merge）
- 取り込み後の全 suite（worktree）: 424 examples, 0 failures, 2 pending。head の CI run 45412098750 green
- PR #121 → main `946838c`（セッションがマージ。止まらずに進めてよい範囲の実装、head の CI green、競合なし）

## R15 ゲート報告: 評価 v2 に足す S2 の経路の問い（作業列 3。ゴールドの確定は人間）（2026-11-24）

**判断を求めること**: (1) 案の 3 問（`spec/fixtures/evaluation/v2/aql_s2.yml`、draft）を、臨床のレビューで確定してよいか。
(2) 確定済みの a001〜a005 に `selection` を足してよいか（下の YAML。ゴールド本体なので、セッションは足していない）。

### 入れたもの（枠組み。計画書 `docs/design/s1-eval-v2-plan.md` 8 節）

- aql の問いは `selection`（クエリビルダーへの入力）を持てる。`Evaluation::BuilderRoute` が、selection → ビルダー → リンタ → 期待行との照合で採点する
- 結果は 一致／不一致／実行不能／組めない。報告に「aql: S2 の経路」の節（母数が 0 なら出さない）
- Red／Green: 読み込みと採点器は `uninitialized constant Evaluation::BuilderRoute` → 49 examples, 0 failures。集計と報告は 16 examples, 2 failures → 61 examples, 0 failures
- 訂正: 計画書 8 節は、実装のコミットのあとに書いた（先に書くべきだった）。中身は実装と同じ

### 案の 3 問と実測（demo_initial。案を active と見なして採点。情報）

| id | 問い | 条件型 | 参照 AQL | S2 の経路 |
|---|---|---|---|---|
| a006 | 病名に「糖尿病」を含む記録を、出所の文書名つきで | 包含（LIKE）、横断 | 一致 `[["ProblemList","2型糖尿病"],["jp_referral","2型糖尿病"]]` | 一致 |
| a007 | 診断確度が「疑い」または「確定」の傷病名 | 値集合のコード 2 つ | 一致 `[["高血圧症"],["2型糖尿病"]]` | 一致 |
| a008 | 拡張期血圧が 90 mmHg 未満の記録の、収縮期と拡張期 | 数値（<）、2 列 | 一致 `[[120.0, 80.0]]` | 一致 |

- いまの採点（`RESET=1 bundle exec rake evaluation:run`）: card 4 問 Top-1 4/4、aql 5 問 一致 5/5、draft 3 問（a006〜a008）、保留問 2 問。
  S2 の経路の母数は 0（selection を持つ active の問いがまだ無い）
- 確定済みの a001〜a005 と同じ選択を組むと、5 問とも期待行に一致する（`spec/lib/query_builder/runner_spec.rb` が固定。R11）

### 人間に問うこと（案の notes にも書いた）

1. a006: 「糖尿病を含む」は臨床の問いとして自然か
2. a007: demo_initial に「確定」の記録が無い。期待行が a002 と同じになる問いを置く意味があるか
3. 日付の範囲の問いを置けない: demo_initial の problem_diagnosis 3 件は、発症日時（at0077）がすべて空（実測）。
   日付の条件を測るには、初期データに発症日時のある記録が要る（初期データは書く側。足すなら別に裁定が要る）
4. a001〜a005 に足す `selection`（下）

```yaml
# a001
selection:
  columns: [ { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 } ]
  conditions:
    - { card: { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 }, operator: ">", value: 110 }
# a002
selection:
  columns: [ { archetype_id: openEHR-EHR-EVALUATION.problem_diagnosis.v1, at_code: at0002 } ]
  conditions:
    - { card: { archetype_id: openEHR-EHR-EVALUATION.problem_diagnosis.v1, at_code: at0073 }, operator: MATCHES, value: [at0074] }
# a003
selection:
  columns: [ { archetype_id: openEHR-EHR-EVALUATION.problem_diagnosis.v1, at_code: at0002 } ]
  conditions:
    - { card: { archetype_id: openEHR-EHR-EVALUATION.problem_diagnosis.v1, at_code: at0002 }, operator: MATCHES, value: ["2型糖尿病", "高血圧症"] }
  composition_name: true
# a004
selection:
  columns: [ { archetype_id: openEHR-EHR-CLUSTER.laboratory_test_analyte.v1, at_code: at0001 } ]
  conditions:
    - { card: { archetype_id: openEHR-EHR-CLUSTER.laboratory_test_analyte.v1, at_code: at0024 }, operator: "=", value: "空腹時血糖" }
# a005
selection:
  columns: [ { archetype_id: openEHR-EHR-OBSERVATION.height.v2, at_code: at0004 } ]
  conditions:
    - { card: { archetype_id: openEHR-EHR-OBSERVATION.height.v2, at_code: at0004 }, operator: ">=", value: 170 }
```

### 残した制約

- カードを `{archetype_id, at_code}` で指すので、同じアーキタイプ・同じ at-code が 1 つのテンプレートに複数ある場合（jp_referral の organisation at0001 が 3 か所）は、最初の 1 枚に当たる。いまの問いには無い


## R16 条件を足す（R-20261125-6）: OR と NOT EXISTS が実行の経路で通るかの確認（2026-11-25）

- 基準点: anlage main `79ebcc4`。`Gemfile.lock` は openehr 2.5.0、openehr-rails 0.9.0
- やり方: リポジトリの外の一時の spec で、demo_initial（`Evaluation::Datasets.build`）の上の AQL を
  `QueryBuilder::Linter.lint` と `OpenehrRails::Aql::Executor.execute` に通した
- 実測（設計書 7.1 の表）: `NOT EXISTS <確度>`、`MATCHES … OR NOT EXISTS …`、`(… OR …) AND …`、数値の `< … OR > …` は、どれもリンタの指摘なしで実行でき、
  行は手で数えたとおりだった（傷病 3 件のうち確度の記載が無いのは 1 件。血圧は 120／80 の 1 件）
- 結論: いまの版のまま通る。止まる条件（通らなければ報告）には当たらない。上流の候補に足すものは無い
- 読んだソース: `openehr-2.5.0/lib/openehr/aql/engine/predicate_evaluator.rb`（`Model::OrExpr`・`NotExpr`・`ExistsExpr` の分岐）

## R17 自己承認した判断（設計書 7 節。R-20261125-6 の範囲内）

| # | 判断 | 捨てた案 |
|---|---|---|
| H1 | 「未記入」は `NOT EXISTS <項目の value のパス>` で書く | 要素（`items[at…]`）に対する NOT EXISTS（実測ではどちらも同じ行。カードのパスをそのまま使えるほうにした） |
| H2 | 「未記入を含む」は値集合の条件だけ | 数値・日付・文字列にも付ける（裁定の対象は値集合。広げるなら別に計画する） |
| H3 | 「範囲の外」は下限と上限の両方を求め、下限 > 上限は組まない | 片方だけを許す（ふつうの比較と同じになる）。下限 > 上限を許す（すべての記録に当たる） |
| H4 | OR を含む条件は、1 つだけのときも括弧でくくる | AND と並ぶときだけくくる（組む AQL の形が条件の数で変わる） |
| H5 | 画面の「どちらかを満たす」は、条件ごとのチェック「前の条件と「または」でつなぐ」で作る | 組を作る別の操作（JavaScript か、画面の遷移が増える。G4 のまま、状態は URL だけにした） |
| H6 | 「範囲の外」を選んで組み直すと、入力が「下限」「上限」に替わる。替わる前の 1 回は「下限と上限の両方が要る」と出る | 値・下限・上限を常に並べる（どの入力が効くかが分かりにくい） |

## R18 サイクル: ビルダー（`37a6e49`）

- Red（`bundle exec rspec spec/lib/query_builder/builder_spec.rb`。17 examples, 6 failures）:

  ```
  1) 未記入を含む: …
       expected: "WHERE (ev/data[at0001]/items[at0073]/value/defining_code/code_string MATCHES {\"at0076\"} OR NOT EXISTS ev/data[at0001]/items[at0073]/value)"
            got: "WHERE ev/data[at0001]/items[at0073]/value/defining_code/code_string MATCHES {\"at0076\"}"
  2) 範囲の外: …                       QueryBuilder::Builder::InvalidSelection
  3) どちらかを満たす: 別々の項目 …     KeyError
  4) どちらかを満たす: 節が 2 つの条件 … KeyError
  5) 組めない選択は InvalidSelection で止める
       expected QueryBuilder::Builder::InvalidSelection with message matching /未記入を含むは、値集合の条件にだけ/ but nothing was raised
  6) 組んだ AQL はどれもリンタを通る    QueryBuilder::Builder::InvalidSelection
  ```

  （その前に 2 回、spec の文字列リテラルの区切りの誤りで SyntaxError になった。実装に入る前に直した）
- Green: `Builder` に `include_missing`、`OUTSIDE`、`{ any: […] }`。`spec/lib/query_builder` 43 examples, 0 failures

## R19 実行とリンタの pin（`85d743f`。実装の変更なし）

- `runner_spec` に 3 例（demo_initial の上で: 確定 0 行 → 未記入を含めて 1 行、疑い＋未記入で 3 行。範囲の外 1 行／0 行。どちらかを満たす 1 行／0 行）
- `linter_spec` に 3 例（MATCHES と NOT EXISTS の OR は指摘なし。NOT EXISTS の中の存在しない節は error〔パス〕。OR の中の型の不一致と値集合に無いコードは error）
- どれも書いた時点で通った（Red にならない）。リンタは OR・NOT・EXISTS の中をもとから辿っていたため。仕様の固定として残す。49 examples, 0 failures

## R20 サイクル: 画面（`ab87545`）

- Red（`bundle exec rspec spec/requests/queries_spec.rb`。17 examples, 6 failures）: 新しい 5 例（入力が無い、AQL に OR が無い、`conditions[0][low]` が無い など）と、
  数値の演算子の一覧を固定していた既存の 1 例（ビルダーの `OPERATORS` に OUTSIDE が入ったため `got: [">", ">=", "<", "<=", "=", "OUTSIDE"]`）
- Green: `QueriesController`（`include_missing`・`low`・`high`・`or`、続く「または」を 1 つの組にまとめる）、ビュー、語彙表（同じコミット）。
  既存の 2 つの pin（演算子の一覧、値集合の条件のラベルの一覧）は、足した入力に合わせて更新した
- 実ブラウザの spec に 2 例。1 例は、期待する AQL の文字列を書き間違えて落ちた（「範囲の外」は自分の括弧を持つので `> 110) OR …`）。spec を直した
- 全 suite: 509 examples, 0 failures, 2 pending

## R21 残っていること

- 評価の問いの `selection` の形に、この 3 つの条件はまだ無い（`Evaluation::Questions.selection`）。問いの案を出すときに足す（設計書 7.6）
- 評価の問いの案は、サンプルデータ（R-20261125-5、書く側）が main に入ってから
- いまの初期データでは、「どちらかを満たす」の両側が別々の記録で当たる例を作れない（血圧が 1 件）。データが増えたら spec に足す

## R22 評価の selection に 3 つの条件を足す（2026-11-25、R-20261125-6。R21 の 1 つめ）

- サンプルデータの実装が main にまだ無く、問いの案は出せない。待たない項目として、`selection` の形だけ先に足した（計画: `docs/design/s1-eval-v2-plan.md` 8.4）
- Red（`bundle exec rspec spec/lib/evaluation/questions_spec.rb spec/lib/evaluation/builder_route_spec.rb`。23 examples, 3 failures）:

  ```
  1) Evaluation::Questions.from_v2 selection の条件に、未記入を含む…、範囲の外…、どちらかを満たす（any）を書ける
     Evaluation::Questions::InvalidQuestion（selection の条件には card と operator が要る）
  2) Evaluation::BuilderRoute どちらかを満たす（any）と範囲の外（OUTSIDE）の selection: 中のカードも索引から引いて組む   KeyError
  3) Evaluation::BuilderRoute any の中の、索引に無いカードは unbuildable                                             KeyError
  ```

  同時に足した 2 例（`include_missing` の採点、`any` が配列でないときの停止）は、書いた時点で通った。
  前者は条件のキーをそのままビルダーに渡していたため、後者はもとの誤りの文に条件の中身（`any`）が出るため。固定として残す
- Green: `Questions.selection_condition`（`any` を再帰で読む）、`BuilderRoute#resolve`（`any` の中のカードも索引から引く）。
  評価の spec と `evaluation_run_spec` で 62 examples, 0 failures
- ゴールド（`spec/fixtures/evaluation/v2/`）は変えていない

## R23 実ブラウザの spec の不安定さを直す（2026-11-25）

- 現象: PR #131 の CI（run 45614802792）で `spec/system/demo_query_builder_spec.rb:100`（範囲の外・どちらかを満たす）が落ちた。
  `Unable to find select box "condition_1_operator"`。PR #131 は検索もクエリビルダーも変えていない。同じ spec は main（`5eceeca`、run 45614244452）では通っている
- 原因（推論。再現はさせていない）: 「表示する項目に足す」「条件に足す」を 4 回続けて押していて、あいだに画面の読み直しを待っていない。
  画面の状態は URL だけなので、読み直しの前に次のボタンを押すと、古い画面の状態で送られて前の操作が消える。R20 で足した spec の書き方の誤り
- 直し: ボタンを押すたびに、項目・条件の数が増えたことを待つ（`have_css(…, count:)`）。同じ形のほかの 3 例にも待ちを足した。実装は変えていない
- 確認: `bundle exec rspec spec/system/demo_query_builder_spec.rb` を 3 回続けて、3 回とも 5 examples, 0 failures

## R24 版をまたいで引く（2026-11-25、R-20261125-10、`skoba/anlage#154`）: 探索と、自己承認した判断

- 計画: `docs/design/s2-cross-version-plan.md`。基準点: anlage main `60a35ae`
- 実測（リポジトリの外の一時の spec。demo_initial に blood_pressure.v1 の記録を 1 件足した上で）
  - v1 と v2 の収縮期・拡張期のカードは、at-code、パス、型、単位（mm[Hg]）、値の範囲（0 以上 1000 未満）が同じ
  - `CONTAINS (OBSERVATION o[…v1] OR OBSERVATION o2[…v2])` は `OpenEHR::AQL::SemanticError: unbound variable: "o"`。
    述語なしの `OBSERVATION o` と `o/archetype_node_id` は `UnsupportedFeature`。版ごとの別々の AQL は、どちらも実行できる
  - v1 のテンプレート（patient_blood_pressure.v1）の帳票の項目名は `blood_pressure_systolic`・`blood_pressure_diastolic`
    （`Template#fields`）。はじめ at-code から推測した名前で保存して、中身が空の記録になった。項目名を読んで直した
- **自己承認した判断**

  | # | 判断 | 捨てた案 |
  |---|---|---|
  | X1 | 版ごとに別の AQL を組み、行をアプリの側でつなぐ | CONTAINS の OR（上の実測のとおり、いまのエンジンでは実行できない） |
  | X2 | 対応の単位は「項目」（版を除いたアーキタイプの ID と at-code）。表は `config/version_mappings.yml` | アーキタイプ単位の対応（ほかの項目まで、確かめずに広がる） |
  | X3 | 最初の候補 2 行は pending で置く。active の行はレビューのあと | セッションが active にする（「使うのは人間がレビューした行だけ」に反する） |
  | X4 | 選ばれたカードに対応の無いものが 1 つでもあれば、組まない | 対応のある項目だけをまたぎ、残りは選んだ版だけで引く（列ごとに版の範囲が違う表になる） |
  | X5 | 索引に片方の版のカードしか無ければ、その版だけを引く | 誤りにする（テンプレートが未登録なだけで落ちる） |
  | X6 | 行をつなぐ順は版の順（v1 → v2）。並べ替えはしない | 日付で並べる（ビルダーに並べ替えが無い。足すなら別に計画する） |
  | X7 | 埋め込み CLUSTER の中の項目の版の対応は、範囲に入れない（確かめたのは、カードのアーキタイプが ENTRY そのものの項目だけ。CLUSTER の項目に行を足したときの挙動は確かめていない） | 途中の述語も版で置き換える（候補が無く、確かめられない） |

## R25 サイクル（版をまたいで引く）

- 候補と表: Red は `uninitialized constant QueryBuilder::VersionCandidates`。Green で `version_mappings_spec` 7 examples, 0 failures
- またいで引く: Red は `ArgumentError: unknown keywords: :across_versions, :mappings`（`cross_version_spec`。出力を途中で切って見たので、
  確かめたのは 9 例のうち 8 例めまで）。
  - **順序の誤り**: はじめの Red は、spec の準備の書き間違い（ハッシュを括らずに渡して `wrong number of arguments`）で落ちていて、意図した理由ではなかった。
    それに気づかないまま実装を書いた。あとで実装をいったん外し、直した spec で意図した Red（上の `unknown keywords`）を取り直した
  - Green: `QueryBuilder::CrossVersion`、`Runner`（`across_versions:`・`mappings:`、`Run#queries`・`version_column?`）。
    もう 1 つ spec の誤り（`Finding` の定数の場所）を直して、関連の spec 148 examples, 0 failures
- 画面: Red は `queries_spec` 21 examples, 3 failures（チェックが無い、版ごとの見出しが無い、理由が出ない）。Green でコントローラ・ビュー・語彙表
- rake: Red は `Don't know how to build task 'query_builder:version_candidates'`。Green で 1 example, 0 failures
- 実ブラウザの spec に 1 例。全 suite: 547 examples, 0 failures, 2 pending
- リンタは変えていない（版ごとの AQL は、これまでと同じ形）

## R26 ゲート報告: 版の対応の行のレビュー

- 候補は 2 件（血圧の収縮期 at0004、拡張期 at0005。v1 と v2）。問うことは `docs/design/s2-cross-version-plan.md` 9 節
- 評価の問いの案（「版をまたいで、収縮期が 140 以上」など）は、サンプルデータが main に入ったあとに、R-20261125-6 の問いの案と一緒に出す

## R27 版の対応の 2 行を active にする（2026-11-26、R-20261125-11）

- Red（先に spec の pin を書き換えた。`spec/lib/query_builder`・`spec/requests/queries_spec.rb`・`spec/lib/tasks/query_builder_spec.rb`、89 examples, 4 failures）:
  リポジトリの表の状態（pending のまま）、既定の表で版をまたいで引く 2 例（「版の対応が無い項目がある」）、rake の出力（pending）
- Green: `config/version_mappings.yml` の 2 行を `status: active` にし、`reviewed_by: Kobayashi, Shinji`、`reviewed_at: 2026-11-25` と、
  確かめた範囲の note を書いた。実ブラウザの spec を含めて 95 examples, 0 failures
- 「対応の無い項目では実行しない」の画面の例は、血圧が active になったので、プロブレム・診断名を使う形に替えた
- これで、画面で「版をまたいで引く」をチェックすると、表を差し替えなくても血圧の v1 と v2 が 1 つの表に出る

## R28 ゲート報告: 評価の問いの案（aql。2026-11-26、R-20261125-6・R-20261125-10）

サンプルデータ（PR #156、main `308b048`）が入ったので、問いを決め直した。**ゴールドを変える PR なので、マージは人間。**
土台は PR #159（版の対応の 2 行を active にする）の上。a014 の S2 の経路が、active の対応の行を使うため。

### やったこと

- 評価の形式: 版をまたぐ問い（`reference_aqls`、`selection.across_versions`）。計画は `docs/design/s1-eval-v2-plan.md` 8.5
  - Red（`questions_spec`・`builder_route_spec`、34 examples, 6 failures）: `unknown keyword: :reference_aqls`（4 例）、読み込みで止まらない、`reference_aqls` を読めない
  - Green: `Question#reference_aqls`、`Questions.reference_aqls`、`AqlScorer`（版ごとに実行して先頭にアーキタイプの ID）、`BuilderRoute#score_across_versions`。
    `spec/lib/evaluation`・`spec/lib/tasks` 92 examples, 0 failures
- 確定済みの a001〜a005 に `selection` を足した。5 問とも、クエリビルダーが組んだ AQL が参照と同じ期待行を返す
- 案（draft）を 7 問にした（`spec/fixtures/evaluation/v2/aql_s2.yml`）。7 問とも、参照 AQL と S2 の経路の両方が期待行に一致する（`builder_route_spec` で固定）

### 案の一覧（期待行は demo_initial での実測）

| id | 問い | 条件の型 | 期待行 | 条件が効いていないと |
|---|---|---|---|---|
| a006 | 病名に「糖尿病」を含む（出所つき） | 部分一致 | 4 行（2型糖尿病 3、糖尿病性腎症 1） | 15 行 |
| a009 | 収縮期 100 未満（低血圧）の、収縮期と拡張期 | 数値 | 2 行（88/54、96/60） | 11 行 |
| a010 | 収縮期 140 以上、または拡張期 90 以上（高血圧） | どちらかを満たす | 4 行（148/86、152/92、132/94、128/92） | 11 行。収縮期だけなら 2 行 |
| a011 | 収縮期が 100〜139 の範囲の外 | 範囲の外 | 4 行（88、96、148、152） | 11 行 |
| a012 | 確定の病名（確度の記載が無いものを含む。出所つき） | 未記入を含む | 11 行（確定 9、記載なし 2） | 15 行。未記入を含めないと 9 行 |
| a013 | 発症が 2025 年の病名（出所と発症日時つき） | 日付の範囲 | 3 行 | 15 行 |
| a014 | 版をまたいで、収縮期 140 以上 | 版をまたぐ | 6 行（v1 の 4、v2 の 2） | v2 だけなら 2 行 |

- 裁定が挙げた 6 つ（低血圧、高血圧、確定の病名、疑いの病名、発症日の範囲、病名の部分一致）のうち、「疑いの病名」は確定済みの a002 が担う（新しい問いは足していない）
- a006 の注記に「部分一致はつなぎで、本来はコードで引く」と書いた
- 旧い案の a007（「疑い」または「確定」）と a008（拡張期 90 未満）は置き換えた

### 採点（`RESET=1 bundle exec rake evaluation:run`）

| | 前（main `f6df2bd`） | この PR |
|---|---|---|
| aql 5 問（参照） | 一致 5/5 | 同じ |
| aql: S2 の経路 | 母数 0 | 5 問、一致 5/5 |
| draft | 3 問（a006〜a008） | 7 問（a006、a009〜a014） |
| card | 変えていない | 同じ |

### 問うこと（臨床のレビュー）

1. **7 問のうち、どれを確定するか**。問いの文言が臨床的に自然か
2. **閾値**: 低血圧は収縮期 100 未満、高血圧は収縮期 140 以上または拡張期 90 以上、範囲は 100〜139。サンプルデータの「判定の目安」をそのまま使った
3. **a012（確定の病名）**: 紹介状の「狭心症」（確度の記載なし）が入る。同じ患者の ProblemList では「疑い」。確度を書かない文書の病名を確定として引く、という決めのとおりだが、この行を期待行に入れてよいか
4. **a006（部分一致）**: つなぎの問いとして評価に置いてよいか。コードで引く問い（ICD-11 5A11）を足すなら、コードを持つ記録が 1 件しか無い
5. **a014（版をまたぐ）**: 期待行の先頭の列は、アーキタイプの ID（版つき）。この形でよいか
6. **a001〜a005 に足した `selection`** は、確定済みの問いへの追記。参照 AQL と期待行は変えていない

### 自己承認した判断

| # | 判断 | 捨てた案 |
|---|---|---|
| Q1 | 版をまたぐ問いの参照は、版ごとの AQL の表（`reference_aqls`）で持つ | 1 本の AQL（いまのエンジンでは書けない。上流の候補 29 項）。参照を持たない問い（ゴールドの健全性を見られない） |
| Q2 | 旧い案の番号（a007・a008）は使い回さず、新しい問いは a009 から | 番号を詰める（ログや PR の記述と食い違う） |
| Q3 | 「疑いの病名」は新しい問いを足さず、a002 に `selection` を足す | 同じ中身の問いを draft で重ねる |

## R29 レビューの結果の反映（2026-11-26、R-20261126-5）

- 7 問（a006、a009〜a014）を確定した: `status: draft` を外し、`reviewed_by: Kobayashi, Shinji`、`reviewed_at: 2026-11-26`。
  notes の「人間に問う」を、決まったこと（閾値はサンプルデータの「判定の目安」、a006 はつなぎの問い、a014 の先頭の列は版つきのアーキタイプ ID）に書き換えた
- サンプルデータの直し（書く側のファイル。この 1 行は、この PR で直してよいと裁定にある）
  - `app/lib/demo/sample_records.yml` の DEMO-05 の紹介状の「狭心症」に `certainty: at0074`（疑い）を足した
  - 紹介状の読み込み（`app/lib/demo/sample_compositions.rb` の `commit_referral`）は、確度を書かない作りだった。行に `certainty` があるときだけ、
    診断確度の ELEMENT（at0073）を足すようにした。項目の名前と値の表示は jp_referral.opt から引く。DEMO-01 の紹介状は、確度を書かないまま
  - Red: `spec/tasks/demo_reset_spec.rb:78`（傷病名 15 件の診断確度とコード）の DEMO-05 の紹介状の行を `at0074` に書き換えて、1 failure。Green で 8 examples, 0 failures
  - 設計書 `docs/design/sample-data-plan.md` の表と集計を合わせた（疑い 3 → 4、記載なし 2 → 1）
- **この直しで期待行が変わった問い**

  | 問い | 前 | あと |
  |---|---|---|
  | a002 診断確度が「疑い」の傷病名（確定済み） | 3 行（高血圧症、起立性低血圧、狭心症） | 4 行（紹介状の狭心症が加わる） |
  | a012 確定の病名（確度の記載が無いものを含む） | 11 行（確定 9、記載なし 2） | 10 行（確定 9、記載なし 1。紹介状の狭心症が外れる） |

  ほかの問い（a001、a003〜a006、a009〜a011、a013、a014）は変わらない。a013（発症が 2025 年）は紹介状の狭心症を含むが、確度は見ていないので 3 行のまま
- 追随した spec の pin（全 suite で 11 failures。どれも「疑い」の行数か「確定＋未記入」の行数を固定していた）:
  `aql_scorer_spec`、`builder_route_spec`（2）、`evaluation/runner_spec`（2）、`query_builder/runner_spec`（2）、`queries_spec`（2）、`demo_query_builder_spec`（2）。
  あわせて、問いの数の pin（`questions_spec`、`evaluation/runner_spec`）を、draft 7 問 → 確定に合わせた
- 採点（確定のあと。`spec/lib/evaluation/runner_spec.rb` で固定）: aql 12 問、参照 12/12 一致、S2 の経路 12/12 一致。draft は 0 問
- 全 suite: 612 examples, 0 failures, 2 pending
- `spec/demo/`（デモクエリの期待件数）は、この直しで変わらなかった（全 suite で落ちていない）

## R30 出所の列を template_id に切り替える（2026-11-26、R-20261126-8 の作業列 1、#183）

自己承認。条件（openehr 2.6.1・openehr-rails 0.11.0 が main に入ること）は、anlage main `46104c6`（#178）で満たした。

### 先に確かめたこと（実測。worktree の dev DB、`rake demo:reset` のあと）

- `SELECT c/archetype_details/template_id/value, c/name/value FROM EHR e CONTAINS COMPOSITION c` の 65 行:

  | template_id | Composition の名前 | 件数 |
  |---|---|---|
  | ProblemList | ProblemList | 13 |
  | CardiologyEncounter | CardiologyEncounter | 11 |
  | LabResultReport | LabResultReport | 26 |
  | bmi_calculation | bmi_calculation | 7 |
  | jp_referral | jp_referral | 2 |
  | patient_blood_pressure.v1 | COLNEC Patient Blood Pressure.v0 | 6 |

  名前と template_id が違うのは、血圧 v1 のテンプレートだけ。評価の問いで出所の列を使うのは傷病名の 4 問で、どれも ProblemList と jp_referral の記録だけを返す
- リンタは `c/archetype_details/template_id/value` を error にしない（`builder_spec` の「組んだ AQL はどれもリンタを通る」）

### Red → Green

- Red 1（`spec/lib/query_builder/builder_spec.rb`。キーワードを `template_id:`、先頭の射影を `c/archetype_details/template_id/value` に書き換えて）:
  `ArgumentError: unknown keyword: :template_id`、17 examples, 2 failures
- Green 1: `Builder`・`Runner`・`Evaluation::BuilderRoute`・`Evaluation::Questions`・コントローラ・画面を切り替えて、17 examples, 0 failures
- Red 2（`spec/requests/queries_spec.rb`「以前の URL（composition_name=1）も、テンプレートの列として受ける」）:
  AQL に `SELECT c/archetype_details/template_id/value,` が無く、1 failure。
  **順序の乱れ**: この受け口は Green 1 のときに先に書いてしまっていた。いったん外して、Red を取り直した
- Green 2: コントローラで `params[:composition_name]` も受けて通る

### 評価の問い（書き換えた 4 問と、前後の値）

| 問い | 参照 AQL の先頭の列（前 → あと） | 期待行（前 → あと） |
|---|---|---|
| a003 2型糖尿病または高血圧症 | `c/name/value AS composition_name` → `c/archetype_details/template_id/value AS template_id` | 7 行のまま（ProblemList 6、jp_referral 1） |
| a006 病名に「糖尿病」を含む | 同じ | 4 行のまま（ProblemList 3、jp_referral 1） |
| a012 確定の病名（未記入を含む） | 同じ | 10 行のまま（ProblemList 9、jp_referral 1） |
| a013 発症が 2025 年の病名 | 同じ | 3 行のまま（ProblemList 2、jp_referral 1） |

- `selection` のキーは `composition_name: true` → `template_id: true`
- 期待行の値は 1 つも変わらない（この 2 つのテンプレートでは、名前と template_id が同じ字面）
- notes は、a003 の「template_id に届かない」を書き換え、ファイルの冒頭に切り替えの日付を足した
- **問いの文言（query）は変えていない**。4 問とも「出所の文書名つきで」のまま。文言を「テンプレート」に改めるかは、人間のレビューの範囲として残す
- 採点（`rake evaluation:run RESET=1`）: aql 12 問、参照 12/12 一致、S2 の経路 12/12 一致

### 自己承認した判断

| # | 判断 | 捨てた案 |
|---|---|---|
| T1 | 列の見出しは「テンプレート」、チェックは「テンプレートも表示する」。パスカードのカードの項目名、クエリビルダーの「<項目名>（<テンプレート>）」と同じ語 | 「文書名」のまま（中身が名前でなくなる）。「template_id」（画面に英字の識別子名を出す） |
| T2 | コードのキーワード、ゴールドの `selection` のキー、URL のパラメータを `template_id` に改める。以前の URL（`composition_name=1`）は同じ列として受ける | 名前を `composition_name` のまま残す（中身と名前が食い違う）。以前の URL を受けない（保存してある URL から列が消える） |
| T3 | デモクエリ 2・3（`docs/demo/aql-queries.md`、`spec/demo/aql_queries_spec.rb`）の `c/name/value` は触らない。クエリビルダーの列ではなく、書く側の範囲 | あわせて書き換える（裁定の範囲の外） |

全 suite: 615 examples, 0 failures, 2 pending。rubocop は違反なし
