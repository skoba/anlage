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
