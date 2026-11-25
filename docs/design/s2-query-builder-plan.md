# S2（クエリビルダーとリンタ）の設計

裁定 ID: R-20261124-11（作業列 4・5）。進め方は R-20261124-8（設計書を push してそのまま実装に進む）。
状態: **リンタは main（PR #96）。ビルダーの本体と画面は 6 節（R-20261124-21）**。LLM は使わない。

- 基準点: anlage main `c09d72f`（openehr 2.4.3、openehr-rails 0.8.0）
- 出口: パスカードを選ぶ → 型に応じた条件を付ける → AQL が組まれる → 実行の前にリンタ（パスの実在・型・値集合）を通る。
  アーキタイプの知識（カード）だけで動く決定的な経路。S4（自然言語→AQL）は LLM の出力をこのリンタに通す
- 進行ログ: `docs/reports/s2-query-builder-log.md`（R1〜）
- 評価: S1 の `aql` 種の採点器（`Evaluation::AqlScorer.score(question, aql:)`、PR #84）に、ビルダーが組んだ AQL を渡して測る
- コード値の条件は openehr 2.5.0（#49）のあと。それまで値集合の**表示文字列**の一致で仮置き（R-20261124-11 の 5）

## 1. いまの状態（実測）

- AQL の実行は `OpenehrRails::Aql::Executor.execute(aql)`。その前段 `QueryValidator`（openehr-rails 0.8.0 `lib/openehr_rails/aql/query_validator.rb`）は
  構文（`OpenEHR::AQL.parse` → `ParseError`／`SemanticError` → `InvalidQuery`）と、エンジンが永続的に未対応のもの（VERSION 系の FROM、
  `TERMINOLOGY(...)` の MATCHES、WHERE の関数呼び出し）だけを見る。**パスの実在・型・値集合は見ない**
- パスの誤りは実行時に出る: 到達できない属性は `UnsupportedFeature: unsupported path attribute "…"`（`path_evaluator.rb:78-84`）、
  存在しないノードは単に 0 行（誤りが見えない）
- 構文木は `OpenEHR::AQL::Model`（openehr 2.4.3 `lib/openehr/aql/model/*.rb`）: `Query`（select／from／where）、`ClassExpression`
  （class_name・variable・predicate）、`Containment`（parent・child）、`IdentifiedPath`（variable・path）、`ObjectPath`／`PathPart`
  （attribute・predicate）、`ArchetypePredicate`（archetype_id・value）、`NodePredicate`（code・value）、`Comparison`（left・operator・right）、
  `MatchesExpr`／`MatchesValueList`（items）、`Literal`（value）。すべて freeze された値オブジェクトで、歩くだけでよい
- カード（`Template.active` の `pathcards`、スキーマ v1.2）は `identity.path`（例 `/content[openEHR-EHR-OBSERVATION.blood_pressure.v2]/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value`）、
  `semantics.rm_type`（DV_QUANTITY／DV_CODED_TEXT／DV_TEXT／DV_DATE_TIME…）、`constraints.value`（DV_QUANTITY: units・magnitude_range、
  DV_CODED_TEXT: `code_list: [{code, label}]`。外部値集合のときは空）を持つ。埋め込み CLUSTER はパスに `items[openEHR-EHR-CLUSTER.x.v1]` が入り、
  SECTION 配下の ENTRY は `/content[openEHR-EHR-SECTION.x.v0]/items[openEHR-EHR-EVALUATION.y.v1]/…`（jp_referral の golden）
- エンジンの制約（`docs/upstream-candidates.md`）: 10 項 `defining_code`、11 項 `events/time`、25 項 `archetype_details` に到達できない
  （終端ホップは `magnitude`／`name`／`value` のみ）。24 項 name 述語（openehr-ruby#60）。これらはリンタが**先に**言う
- 既存の画面は `GET /pathcards/search`（`PathcardsController#search`、カード検索）。routes とレイアウトは書く側と共有（あとから触る側が rebase）

## 2. 設計

### 2.1 リンタ（先に作る）

`QueryBuilder::Linter.lint(aql, cards: QueryBuilder::Corpus.active)` → `Lint`（`findings`、`ok?`）。実行はしない。

| 検査 | 内容 | 根拠 |
|---|---|---|
| 構文 | `OpenEHR::AQL.parse`。失敗は `error`（構文） | `QueryValidator#parse` と同じ |
| 永続的に未対応 | `QueryValidator.validate!` を呼び、`UnsupportedFeature` を `error` に写す | 二重に実装しない |
| 変数 | SELECT／WHERE の `IdentifiedPath.variable` が FROM で宣言されている | `ClassExpression.variable` |
| 結び付け | 変数 → （class_name, archetype_id）。`ArchetypePredicate` の無い変数（`c`、`e`）はパス検査の対象外（`info`） | — |
| パスの実在 | 変数のアーキタイプを持つカードのうち、**アーキタイプのルートから下の節パス**（カードの path を、述語が archetype_id の節で切り、末尾の `/value` を落としたもの）が AQL の節パス（述語を持つ最後の `PathPart` まで）と一致するものがあるか。無ければ `error` に同じアーキタイプの候補パスを添える | `identity.path` |
| 終端ホップ | 節のあとのホップ列が、カードの `rm_type` に許されるものか。DV_QUANTITY・DV_COUNT: `value/magnitude`（`value/units` は現行エンジンの終端ホップに無く届かない。R5 で訂正）／DV_CODED_TEXT・DV_TEXT・DV_DATE_TIME・DV_BOOLEAN: `value/value`／どれも `value` 単独（RM オブジェクトの射影）。エンジンが届かないホップ（`defining_code`、`time`、`archetype_details`）は `error` に上流候補の項番を添える | `ALLOWED_TERMINAL_HOPS`、10・11・25 項 |
| 型 | `Comparison` のリテラルの型と終端の型が合うか（`magnitude` は数値、`value/value` は文字列。DV_DATE_TIME の `value/value` は ISO 8601 として読めること） | `Literal.value` の Ruby 型 |
| 値集合 | DV_CODED_TEXT で `code_list` のあるカードに対する `=`／`MATCHES` のリテラルが、`code_list[].label` に含まれるか。含まれなければ `error` に許される値を添える。`code_list` が空（外部値集合）なら `info`（検査できない） | `constraints.value.code_list` |
| name 述語 | `ArchetypePredicate.value`／`NodePredicate.value` が付いていれば `warning`（24 項、openehr-ruby#60 の解消まで兄弟に fan-out） | 24 項 |

`Finding` は `severity`（error／warning／info）、`code`（上の行の名）、`message`、`path`（問題の AQL 片）。`ok?` は error が無いこと。
文言は `docs/demo/ui-vocabulary.md` に載せる（画面に出すときに同じコミットで）。

### 2.2 ビルダー（リンタのあと）

`QueryBuilder::Builder.build(selection)` → AQL 文字列。入力は**カードの参照と条件**だけ（自然言語は入らない）:

```ruby
{
  columns: [ { card: "<template_id>|<path>" } ],                    # 射影するカード
  conditions: [ { card:, operator: ">" | ">=" | "<" | "<=" | "=" | "MATCHES" | "BETWEEN" | "CONTAINS", value: ... } ],
  compositions: { name: true }                                       # 出所の並記（c/name/value）
}
```

- 型に応じた条件（ロードマップ S2）: DV_QUANTITY → 数値比較（`>`…）、DV_CODED_TEXT（code_list あり）→ 値集合（`MATCHES {…}`、表示文字列で仮置き）、
  DV_DATE_TIME → 日付範囲（`>=` AND `<`、ISO 文字列の辞書順。デモクエリ 4 と同じ前提）、DV_TEXT → 包含（`LIKE`）または一致（`=`）
- FROM はカードの path から組む: `/content[X]/…` → `CONTAINS <RM 型> v[X]`、SECTION 配下は `CONTAINS SECTION s[S] CONTAINS <RM 型> v[X]`、
  埋め込み CLUSTER は CONTAINS にしない（パスの `items[CLUSTER]` で辿る）。同じアーキタイプが複数テンプレートにあれば 1 本の変数で横断（デモクエリ 5）
- 組んだ AQL は必ずリンタを通してから `Executor` に渡す。リンタの error があれば実行しない

### 2.3 画面（最後）

`GET /queries/new`（カード検索 → 選ぶ → 条件 → AQL のプレビューとリンタの結果 → 実行 → 行）。routes・レイアウト・`ui-vocabulary.md` は共有ファイルなので、
着手時に `origin/main` を取り込んでから触る。system spec は実ブラウザ（`js: true`）。

### 2.4 置き場所

| 役 | ファイル |
|---|---|
| コーパス（active のカードを archetype_id で引く） | `app/lib/query_builder/corpus.rb` |
| リンタ | `app/lib/query_builder/linter.rb`、`app/lib/query_builder/finding.rb` |
| ビルダー | `app/lib/query_builder/builder.rb` |
| 画面 | `app/controllers/queries_controller.rb`、`app/views/queries/`、`config/routes.rb` |
| spec | `spec/lib/query_builder/linter_spec.rb`、`builder_spec.rb`、`spec/requests/queries_spec.rb`、`spec/system/demo_query_builder_spec.rb` |

## 3. テスト TODO（リンタ。Red から始める spec の見出し）

1. 「構文の誤りは error（構文）1 件になり、ok? は false」
2. 「FROM で宣言していない変数を SELECT／WHERE に使うと error（変数）」
3. 「存在する節パス（CardiologyEncounter の血圧 at0004）は findings 無しで ok?」
4. 「存在しない節（items[at0099]）は error（パス）で、同じアーキタイプの候補パスを添える」「SECTION 配下の ENTRY（jp_referral の problem_diagnosis）は節パスをルートから相対に切って見つける」
5. 「DV_TEXT のカードに value/magnitude は error（終端ホップ）」「value/defining_code/code_string は error に上流候補 10 項を添える」
6. 「magnitude と文字列リテラルの比較は error（型）」「DV_DATE_TIME の value/value に ISO 8601 で読めない文字列は error（型）」
7. 「診断確度 at0073 の MATCHES {"疑い", "推定"} は ok?、{"疑惑"} は error（値集合）に許される値（疑い／推定／確定）を添える」「code_list の無い DV_CODED_TEXT（at0002）は info」
8. 「name 述語（[openEHR-EHR-CLUSTER.organisation.v1, '紹介先医療機関']）は warning（24 項）」
9. 「`QueryValidator` が拒むもの（VERSION の FROM）は error に写す」

ビルダーと画面の TODO はリンタの出口で足す（ビルダーの Red は「血圧 at0004 > 110 の選択から、デモクエリ 1 と同形の AQL が組まれ、リンタを通る」から）。

## 4. 自己承認した判断

| # | 判断 | 捨てた案 |
|---|---|---|
| D1 | リンタはカード（`Template.active` の pathcards）だけを知識源にする。OPT を再解析しない | OPT の再解析（抽出器と二重になる） |
| D2 | 構文と永続未対応は `QueryValidator` を呼んで写す | 自前で再実装 |
| D3 | 節パスの照合は「アーキタイプのルートから下」で行う（SECTION 配下・埋め込み CLUSTER を同じ規則で扱う） | `/content[...]` 固定の前置き（jp_referral で破れる） |
| D4 | コード値の条件は表示文字列で仮置きし、リンタは `defining_code` を error で止める | 2.5.0 を待って S2 全体を止める |
| D5 | 名前空間 `QueryBuilder`、`app/lib/query_builder/` | `Aql::Linter`（gem の名前空間と紛れる） |

## 5. 範囲外

自然言語→AQL（S4）、検索の改良（S3）、AQL エンジンの拡張（openehr-ruby）、コード値での条件（2.5.0 のあと）、SNOMED 等の外部値集合の展開（コンテンツ防火壁）。

## 6. ビルダーの本体と画面（R-20261124-21 の作業列 1・2。2.2・2.3 を、openehr 2.5.0 のあとの形に改める）

基準点: anlage main `66f3a85`（openehr 2.5.0、openehr-rails 0.9.0）。この節が 2.2・2.3 と食い違うときは、この節が優先する。

### 6.1 エンジンの変化（実測）

- openehr 2.5.0 の `path_evaluator.rb:23` は `ALLOWED_TERMINAL_HOPS = %w[code_string defining_code magnitude name time value]`。
  `value/defining_code/code_string` に届く（評価 v2 の a002 が main で一致。`docs/reports/s1-eval-v2-log.md` R12）
- `LIKE` は glob（`predicate_evaluator.rb:17-21`: `?` は 1 文字、`*` は 0 文字以上、値の全体に一致）。`*` と `?` を文字として書く方法は無い
- 文字列リテラルは `\\` と `\"` のエスケープを読む（`lexer.rb:74-78`、`read_string`）
- 1 つの節が複数に当たると `fan-out SELECT paths are not yet supported` で落ちる（`path_evaluator.rb:93-96`）。繰り返しのある節（検査の分析項目が 2 つ以上）は
  いまのエンジンでは引けない。ビルダーは防がず、実行時の誤りとして画面に出す

### 6.2 リンタの追随（先に直す）

- 終端ホップに `value/defining_code/code_string` を足す（DV_CODED_TEXT だけ）。エンジンのホップ表は 2.5.0 の実物に合わせる
- 値集合: `code_string` への `=`／`MATCHES` は `code_list[].code` と照合する（表示文字列 `value/value` は従来どおり `label` と照合）
- `archetype_details`（25 項）は届かないままなので error のまま

### 6.3 ビルダー

`QueryBuilder::Builder.build(columns:, conditions:, composition_name:)` → AQL 文字列。入力はカード（ハッシュ）と条件だけで、自然言語は入らない。

- 変数は ENTRY のアーキタイプ 1 つに 1 本。カードの path を、ENTRY（OBSERVATION／EVALUATION／INSTRUCTION／ACTION／ADMIN_ENTRY）の述語の節で切り、
  そこから下をパスにする。埋め込み CLUSTER は `items[openEHR-EHR-CLUSTER.x.v1]` のまま辿る
- FROM は `EHR e CONTAINS COMPOSITION c CONTAINS <RM 型> <変数>[<archetype_id>]`。SECTION は FROM に書かない（CONTAINS は子孫を辿るので、
  SECTION 配下の ENTRY も同じ 1 本で引ける。同じアーキタイプを持つ複数のテンプレートを横断する。デモクエリ 5 と同じ形）
- 1 つのクエリで使える ENTRY のアーキタイプは 1 つ。2 つ以上を選ぶと `InvalidSelection`（結合の意味＝同じ文書の中か、同じ患者かを決めていない）
- 射影: DV_QUANTITY・DV_COUNT は `value/magnitude`、ほかは `value/value`。`composition_name` が真なら先頭に `c/name/value`
- 条件（カードの型で決まる。`QueryBuilder::Builder.kind(card)`）:

| 種類 | カード | 演算子 | AQL |
|---|---|---|---|
| number | DV_QUANTITY、DV_COUNT | `>` `>=` `<` `<=` `=` | `…/value/magnitude > 110` |
| code | DV_CODED_TEXT で code_list がある | `MATCHES`（コードの配列） | `…/value/defining_code/code_string MATCHES {"at0074"}` |
| date | DV_DATE_TIME、DV_DATE | `BETWEEN`（from・to。片方だけでもよい） | `…/value/value >= "from" AND …/value/value < "to"` |
| text | 上のどれでもない（DV_TEXT、外部値集合の DV_CODED_TEXT など） | `=`、`MATCHES`（文字列の配列）、`CONTAINS` | `= "x"`、`MATCHES {"x", "y"}`、`LIKE "*x*"` |

- 値は必ずリテラルとして書く: 数値は `Integer`／`Float` に読めるものだけ、文字列は `\\` と `"` をエスケープする。
  `CONTAINS` の値に `*`・`?` があれば `InvalidSelection`（glob の文字を文字として書けない）
- 条件どうしは AND でつなぐ（OR は作らない。範囲外）
- `QueryBuilder::Runner.call(...)` が、組む → リンタ → error が無ければ `OpenehrRails::Aql::Executor.execute` の順に通す。
  リンタの error があれば実行しない。実行時の誤り（`OpenehrRails::Aql::Error`）は例外にせず結果に持つ

### 6.4 画面

`GET /queries/new`（名前は「クエリビルダー」）。状態はすべて URL のパラメータに持つ（サーバーにもブラウザにも保存しない。JavaScript は使わない）。

- 流れ: 探したい項目で検索 → カードごとに「表示する項目に足す」「条件に足す」→ 条件は種類に応じた入力（数値と演算子／値集合のチェック／日付の範囲／文字列）
  → 「AQL を組む」で AQL とリンタの指摘を出す → 「実行」で行を出す
- カードの参照は `<template_id>|<path>`。active のカードに無い参照は捨てて、その旨を出す
- 共通ナビに「クエリビルダー」を足す（「パスカード検索」と「AQL 照会」のあいだ）。文言は `docs/demo/ui-vocabulary.md` に同じコミットで足す
- 実行するのは、ビルダーが組んだ AQL だけ（URL に AQL を受け取らない）。自由な AQL は既存の「AQL 照会」

### 6.5 テスト TODO

リンタ: 1.「DV_CODED_TEXT の value/defining_code/code_string は通る」「DV_TEXT には error」 2.「code_string の MATCHES は code と照合し、無いコードは error に許されるコードを添える」

ビルダー: 3.「血圧 at0004 > 110 から、評価 v2 の a001 と同じ形の AQL」 4.「診断確度のコード at0074 から a002 と同じ形」 5.「文書名つき・文字列の MATCHES から a003 と同じ形」
6.「埋め込み CLUSTER の分析名 = 空腹時血糖 から a004 と同じ形」 7.「日付の範囲」 8.「SECTION 配下のカード（jp_referral）からも同じ AQL」 9.「包含は LIKE、引用符はエスケープ」
10.「ENTRY が 2 つ・型に合わない演算子・数値でない値・glob の文字・項目なしは InvalidSelection」 11.「組んだ AQL はどれもリンタを通る」

実行: 12.「demo_initial の上で a001〜a005 と同じ行を返す」「リンタの error があれば実行しない」

画面: 13. request spec（検索、足す、AQL、指摘、実行、ナビ） 14. 実ブラウザの system spec（`spec/system/demo_query_builder_spec.rb`、`js: true`。検索 → 条件 → 実行 → 行）

### 6.6 自己承認した判断

| # | 判断 | 捨てた案 |
|---|---|---|
| G1 | SECTION を FROM に書かない | 2.2 の `CONTAINS SECTION s[S]`（テンプレートを横断できなくなる。jp_referral と ProblemList の problem_diagnosis が別の AQL になる） |
| G2 | ENTRY のアーキタイプは 1 クエリに 1 つ | 複数の ENTRY を AND でつなぐ（結合の意味が臨床の判断になる。要るなら別に計画する） |
| G3 | コード値の条件は `defining_code/code_string`。表示文字列の仮置き（D4）をやめる | 表示文字列のまま（言語で変わる。裁定 R-20261124-21 の指示） |
| G4 | 画面の状態は URL だけ。JavaScript を足さない | Stimulus で組み立てる（書く側のレイアウト・JS と重なる。実ブラウザの spec は URL の遷移でも書ける） |
| G5 | 画面は AQL の文字列を受け取らない | プレビューの AQL を編集して実行（「AQL 照会」と役が重なり、リンタを通らない AQL の入口になる） |


## 7. 条件を足す: 未記入を含む、範囲の外、どちらかを満たす（R-20261125-6）

状態: 計画書に追記して、そのまま実装に進む（R-20261125-6）。基準点: anlage main `79ebcc4`（openehr 2.5.0、openehr-rails 0.9.0）。

### 7.1 先に確かめたこと（実測）

demo_initial（傷病 3 件: 高血圧症〔疑い〕、2型糖尿病〔疑い〕、2型糖尿病〔確度の記載なし〕。血圧 1 件: 120／80）の上で、
AQL を `QueryBuilder::Linter.lint` と `OpenehrRails::Aql::Executor.execute` に通した（リポジトリの外の一時の spec。ログ R16）。

| AQL の形 | リンタ | 結果 |
|---|---|---|
| `WHERE NOT EXISTS ev/data[at0001]/items[at0073]/value` | 指摘なし | 確度の記載が無い 1 行 |
| `WHERE <確度のコード> MATCHES {"at0076"} OR NOT EXISTS <確度>` | 指摘なし | 同じ 1 行（「確定」は 0 件、未記入が 1 件） |
| `WHERE (… OR NOT EXISTS …) AND <病名> LIKE "*糖尿病*"` | 指摘なし | 1 行（括弧が効く） |
| `WHERE <収縮期> < 100 OR <収縮期> > 110` | 指摘なし | 1 行。`> 140` にすると 0 行 |
| `WHERE (<収縮期> >= 140 OR <拡張期> >= 80) AND <収縮期> > 200` | 指摘なし | 0 行 |

- OR・NOT EXISTS・括弧は、いまの版のまま通る。上流の候補に足すものは無い
- リンタは、OR・NOT・EXISTS の中のパスと比較をすでに辿る（`linter.rb` の `paths_in`・`conditions`）

### 7.2 ビルダー

`conditions` の要素を 3 つの形で広げる。要素どうしは、これまでどおり AND。OR を含む要素は括弧でくくる。

| 条件 | 入力 | 組む AQL |
|---|---|---|
| 未記入を含む | 値集合（コード）の条件に `include_missing: true` | `(<path>/defining_code/code_string MATCHES {…} OR NOT EXISTS <path>)` |
| 範囲の外 | 数値の条件で `operator: "OUTSIDE"`、`value: { low:, high: }` | `(<path>/magnitude < <low> OR <path>/magnitude > <high>)` |
| どちらかを満たす | `{ any: [条件, 条件, …] }`（2 つ以上） | `(<条件 1> OR <条件 2> …)`。中の条件が 2 つの節を持つとき（日付の範囲）は、その条件を括弧でくくる |

- 「未記入」は、その要素が書かれていないこと（`NOT EXISTS`）。null flavor は見ない（R-20261125-6）
- 「未記入を含む」は値集合の条件だけ。数値・日付・文字列には付けない（付けたら `InvalidSelection`）
- 「範囲の外」は下限と上限の両方が要る。下限が上限より大きいものは `InvalidSelection`（すべての記録に当たる条件になる）
- 「どちらかを満たす」の中に、もう 1 段の「どちらかを満たす」は入れない。1 つのクエリで使える ENTRY のアーキタイプは 1 つ（G2）のまま

### 7.3 リンタ

変えるところは無い見込み（7.1）。OR の中の型の不一致と、`NOT EXISTS` の中の実在しない節が error になることを spec で固定する。

### 7.4 画面

状態は URL だけ、JavaScript なし（G4）のまま。

- 値集合の条件に、チェック「未記入を含む」（`conditions[i][include_missing]`）
- 数値の演算子に「範囲の外」。選んで組み直すと、入力が「下限」「上限」に替わる（`conditions[i][low]`・`[high]`）
- 2 つめ以降の条件に、チェック「前の条件と『または』でつなぐ」（`conditions[i][or]`）。続けてチェックした条件が 1 つの組になる。
  条件のあいだに、つなぎ方（「かつ」／「または」）を出す
- 文言は `docs/demo/ui-vocabulary.md` に同じコミットで足す

### 7.5 テスト TODO

ビルダー: 1.「未記入を含む」 2.「範囲の外」 3.「どちらかを満たす（別々の項目）」「日付の範囲を含む組は括弧」 4.「組めない選択（値集合でない項目に未記入、下限 > 上限、片方だけ、組が 1 つ、入れ子、ENTRY が 2 つ）」 5.「組んだ AQL はリンタを通る」

実行: 6. demo_initial の上で「確定または未記入」「疑いまたは未記入」「範囲の外」「どちらかを満たす」の行

リンタ: 7. OR の中の型の不一致、NOT EXISTS の実在しない節

画面: 8. request spec（3 つの入力と AQL、実行） 9. 実ブラウザの system spec に 1 例

### 7.6 範囲外

- 評価の問いの `selection` の形にこの 3 つを足すのは、問いの案を出すとき（サンプルデータが main に入ったあと）に行う
- 「〜でない」（NOT）だけの条件、OR の入れ子、複数の ENTRY
