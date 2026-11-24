# S2（クエリビルダーとリンタ）の設計

裁定 ID: R-20261124-11（作業列 4・5）。進め方は R-20261124-8（設計書を push してそのまま実装に進む）。
状態: **push 済み・実装中（リンタから）**。LLM は使わない。

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
| 終端ホップ | 節のあとのホップ列が、カードの `rm_type` に許されるものか。DV_QUANTITY: `value/magnitude`・`value/units`／DV_CODED_TEXT・DV_TEXT・DV_DATE_TIME・DV_BOOLEAN: `value/value`／どれも `value` 単独（RM オブジェクトの射影）。エンジンが届かないホップ（`defining_code`、`time`、`archetype_details`）は `error` に上流候補の項番を添える | `ALLOWED_TERMINAL_HOPS`、10・11・25 項 |
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
