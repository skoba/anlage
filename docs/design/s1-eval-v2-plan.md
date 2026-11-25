# S1（評価 v2）の計画

裁定 ID: R-20261124-11（作業列 1〜3）。進め方は R-20261124-8（計画書を push してそのまま実装に進む。統括が事後に読む）。
状態: **push 済み・実装中**。LLM は使わない。

- 基準点: anlage main `6c100e0`（openehr 2.4.3、openehr-rails 0.8.0、Ruby 4.0.10）
- 出口: v1 の 17 問を v2 の枠組みで再現する pin が green、`aql` 種の問いがデータセット上で採点できる、
  ゴールド v2 の案を `draft` で置いてゲート報告（作業列 3。臨床のレビューは人間）
- 進行ログ: `docs/reports/s1-eval-v2-log.md`（R1〜）
- 前身: WP4（`docs/design/wp4-plan.md`、`skoba/anlage#14`）。将来課題節の 3 点（期待集合・負例・保留問）を本計画が引き受ける

## 1. いまの状態（実測）

- 評価器は `lib/tasks/pathcards.rake` の `pathcards:eval` 1 本。`spec/fixtures/pathcards_eval_seed.yml` を読み、
  `Opt::PathcardSearch.call(query)` の結果で `identity.archetype_id` が `expected_archetype_id` に一致する
  最初の順位を rank とする（`expected_at_code` は読み込むだけで採点に使っていない）
- 指標: Top-1・Top-3・完全失敗率・MRR・`intent_tag` 別の hit 数。実行のたびに `docs/reports/wp4-eval-log.md` へ自動追記する
  （2026-08-26 に同一値が 3 回並んだ。自動追記は雑音になっている）
- 母数は 17 問（`draft: true` の q21 を除く）。直近の実測は Top-1 14/17（82.35%）、Top-3 15/17（88.24%）、
  完全失敗 2/17（11.76%）、MRR 0.8529（`spec/lib/tasks/pathcards_eval_spec.rb` が pin）
- ゴールドの注記に、v1 の形式では表せない要求が既に書かれている:
  - 期待集合: q10「血圧」・q14「血圧測定」は {at0004, at0005} の両方が正解（注記に「期待集合の第 1 号」と明記）
  - 順位つき第 2 候補: q08「発症」は at0077 が主、at0002 が第 2 候補
  - 負例: q15 旧クエリ「臨床検査」が ProblemList at0003「臨床的に認識された日時」と bigram「臨床」で偽陽性競合。
    q18 注記「既往歴 → problem_diagnosis は約 2 割しか正しくない」（表層の包含 ≠ 指示対象の包含）
  - 保留問: 「既往歴 → OBSERVATION.story」（q21 draft、jp_referral にのみカードあり）、
    「検体 → CLUSTER.specimen」（コーパスに無く出題不能。v0.3 待ち）
- AQL の実行は `OpenehrRails::Aql::Executor.execute(aql)` → `OpenEHR::AQL::ResultSet`（`columns`・`rows`）。
  デモクエリ 5 件は `spec/demo/` で期待行と照合済み。初期状態は `rake demo:reset`
  （fixture 5 件の登録 ＋ `Demo::SampleCompositions.load!`）で、`spec/demo/cross_template_query_spec.rb` が
  spec の中からこの状態を作って引いている
- エンジンの制約（`docs/upstream-candidates.md` 10・11・24・25 項）: `defining_code`／`events/time`／
  `archetype_details` に到達できない、name 述語が捨てられる。コード値の条件は openehr 2.5.0（#49）待ち
  （R-20261124-11 の 5。それまで値集合の表示文字列の一致で仮置き）
- テスト DB は worktree ごとの SQLite（`config/database.yml` の `storage/test.sqlite3`）。書く側と並行して rspec を回せる

## 2. 設計

### 2.1 問いの形式（YAML）

1 問は `kind`（`card`／`aql`）と `status`（既定 `active`、`draft`、`pending`）を持つ。

```yaml
# kind: card — 問い（日本語）→ 期待するカードの集合
- id: c010
  kind: card
  query: "血圧"
  expected:                       # 期待集合。1 つでも出れば hit、全部出れば recall 1.0
    - { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 }
    - { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0005 }
  match: card                     # card = archetype_id と at_code の両方 / archetype = archetype_id のみ（v1 互換）
  forbidden: []                   # 負例。top-k（既定 3）に出たら「負例違反」
  intent_tag: bigram成立想定
  notes: "..."
  reviewed_by:
  reviewed_at:

# kind: aql — 問い（日本語）→ 参照 AQL をデータセット上で実行した結果
- id: a001
  kind: aql
  query: "収縮期血圧が 110 mmHg を超える記録"
  dataset: demo_initial           # 名前つきデータセット（2.3）
  reference_aql: |
    SELECT o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude AS systolic
    FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2]
    WHERE o/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value/magnitude > 110
  expected_rows: [[120.0]]        # 行の多重集合。ordered: true のときだけ順序も見る
  cards: [ { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 } ]  # 使うカード（S2 の入力）

# status: pending — 正解がコーパスに無い保留問。母数に入れず、期待先がコーパスに現れたら「保留解除候補」として報告する
- id: c019
  kind: card
  status: pending
  query: "検体"
  expected: [ { archetype_id: openEHR-EHR-CLUSTER.specimen.v1 } ]
  pending_until: "CLUSTER.specimen を含む OPT（jp_referral v0.3 等）がコーパスに入る"
```

- `draft` は人間レビュー前（v1 と同じ意味）。`pending` は正解不在。どちらも採点の母数に入れず、件数と理由を報告に出す
- `expected` の要素は `archetype_id` 必須、`at_code` 任意。`match: card` で `at_code` が無い要素は archetype 一致で見る
- `aql` 種の採点対象は **AQL 文字列**（既定は `reference_aql` 自身）。S1 では「参照 AQL が期待行を返す」ことがゴールドの
  健全性の pin になり、S2（クエリビルダーが組んだ AQL）・S4（LLM が書いた AQL）は同じ採点器に別の AQL を渡す

### 2.2 v1 からの移行

- **v1 のゴールド本体（`spec/fixtures/pathcards_eval_seed.yml`）は変更しない**（人間の専有領域。`CLAUDE.md`「評価データの人間レビュー中の編集範囲」）
- v2 の読み込み器に v1 アダプタを置き、各エントリを `kind: card`・`match: archetype`・`expected: [{archetype_id, at_code}]` に写す
  （`draft: true` → `status: draft`）。これで v1 の採点と同じ意味になり、**最初の pin**（Top-1 14/17 ほか）を v2 の枠組みで再現する
- 同じ 17 問を `match: card` でも集計し、at_code まで見たときの数字を報告に並べる（新しい情報。pin ではない）
- v2 固有の問いは `spec/fixtures/evaluation/v2/*.yml` に置く。ゴールドの案は `status: draft` で入れ、ゲート報告で人間に回す
- `pathcards:eval` と `spec/lib/tasks/pathcards_eval_spec.rb` は v2 の pin が green になっても**残す**
  （撤去はファイルの削除＝「必ず止まる」。ゴールド v2 が確定したあとに別の PR で提案する）

### 2.3 データセット

- `demo_initial`: `rake demo:reset` と同じ手順（fixture 5 件を `Template.build_from_opt_xml` → `PathcardExtractor` → save、
  `Demo::SampleCompositions.load!`）で作る初期状態。決定的で、`spec/demo/cross_template_query_spec.rb` が既に spec の中で使っている
- データセットは名前で参照し、実装は `Evaluation::Datasets` に集める。S2 以降で別の初期状態（例: 件数の多いもの）を足せる
- rake からの実行は dev DB に対して行う（`demo:reset` 済みを前提にする。`aql` 種は dataset が `demo_initial` のとき、
  直前に `demo:reset` 相当を走らせるかを `RESET=1` で選ぶ。既定は走らせない＝dev DB を壊さない）

### 2.4 採点

| 種 | 指標 | 定義 |
|---|---|---|
| card | hit@1、hit@3 | 期待集合のどれか 1 つが top-k に出る（v1 の Top-1・Top-3 と同じ。期待集合が 1 要素なら同値） |
| card | recall@3 | top-3 に出た期待要素の数 ÷ 期待集合の大きさ（集合評価。v1 には無い） |
| card | MRR | 期待集合のどれかが最初に出た順位の逆数の平均（出なければ 0） |
| card | 完全失敗 | 期待集合のどれも結果に出ない |
| card | 負例違反 | `forbidden` の要素が top-3 に出る |
| card | intent_tag 別 | hit（top-3 以内）の数 ÷ 問題数（v1 と同じ軸） |
| aql | 一致 | 実行結果の行の多重集合が `expected_rows` と一致（`ordered: true` なら順序も）。不一致は差分（余分・不足の行）を出す |
| aql | 実行不能 | `OpenehrRails::Aql::InvalidQuery`／`UnsupportedFeature` を捕まえて「実行不能」に数える（例外で止めない） |
| 共通 | draft／pending | 件数と理由。pending は期待先のアーキタイプがコーパス（`Template.active` のカード）に現れたら「保留解除候補」 |

行の比較: 数値は Float に、文字列はそのまま、nil はそのまま。RM オブジェクトが返る列は `ResultSet#to_json` と同じ写像で JSON 値に落として比べる。

### 2.5 報告

- `rake evaluation:run` が Markdown を標準出力に出す（見出し、集計表、完全失敗と負例違反の一覧、aql の不一致の差分、draft／pending の一覧）
- **ファイルへの自動追記はしない**（v1 の `wp4-eval-log.md` で同一値の重複が雑音になった実測）。記録はセッションが `docs/reports/s1-eval-v2-log.md` に貼る
- 集計値の regression pin は spec（`spec/lib/evaluation/*_spec.rb`）が持つ。合否は CI

### 2.6 置き場所

| 役 | ファイル |
|---|---|
| 問いの読み込み（v1 アダプタ、v2 YAML、形式の検査） | `app/lib/evaluation/questions.rb` |
| データセット | `app/lib/evaluation/datasets.rb` |
| 実行（card → `Opt::PathcardSearch`、aql → `OpenehrRails::Aql::Executor`） | `app/lib/evaluation/runner.rb` |
| 採点 | `app/lib/evaluation/card_scorer.rb`、`app/lib/evaluation/aql_scorer.rb` |
| 報告（Markdown） | `app/lib/evaluation/report.rb` |
| rake | `lib/tasks/evaluation.rake`（`evaluation:run`） |
| v2 の問い | `spec/fixtures/evaluation/v2/cards.yml`、`spec/fixtures/evaluation/v2/aql.yml` |
| spec | `spec/lib/evaluation/questions_spec.rb`、`card_scorer_spec.rb`、`aql_scorer_spec.rb`、`runner_spec.rb`、`report_spec.rb`、`spec/lib/tasks/evaluation_run_spec.rb` |

名前空間は `Evaluation`（`Eval` は `Kernel#eval` と紛れる）。`app/lib/opt`・`app/lib/demo` と同じ置き方。

## 3. テスト TODO（Red から始める spec の見出し）

1. 読み込み: 「v1 の seed をアダプタで読むと、active 17 問・draft 1 問（q21）の `card` 問いになり、`match` は archetype」
2. 読み込み: 「v2 の YAML は kind ごとの必須キー（card: query・expected／aql: query・dataset・reference_aql・expected_rows）を欠くと読み込みで止まる」「未知の kind・status も止まる」
3. card の採点: 「期待集合の 1 つが 2 位なら rank 1・hit@3・recall@3 は 1/2・MRR 0.5」「forbidden が top-3 に出たら負例違反」「どれも出なければ完全失敗」
4. **最初の pin**: 「4 テンプレートを索引し v1 の 17 問を v2 で走らせると、Top-1 14/17・Top-3 15/17・完全失敗 2/17・MRR 0.8529・intent_tag 別 11/11・4/4・0/2 になる」（`spec/lib/tasks/pathcards_eval_spec.rb` と同じ前提・同じ数字）
5. aql の採点: 「`demo_initial` の上で参照 AQL を実行し、期待行と多重集合として一致すれば一致」「1 行違えば差分（余分・不足）が出る」「`UnsupportedFeature` は実行不能として数える」
6. pending: 「期待先のアーキタイプがコーパスに無い保留問は母数に入らず、一覧に出る」「jp_referral を索引すると story の保留問が保留解除候補になる」
7. 報告: 「Markdown に集計表・完全失敗・負例違反・aql 差分・draft／pending の節がある」
8. rake: 「`evaluation:run` が報告を標準出力に出し、ファイルには書かない」

コミットは 1 サイクル 1 本（Red の出力はログに載せる）。実装の PR は `feat/s1-eval-v2`（計画書の PR とは別）。

## 4. 作業列 3（ゴールド v2 の案。ここで止まる）

案は `status: draft` で `spec/fixtures/evaluation/v2/` に置き、ゲート報告で人間に回す。候補（出所は v1 の注記）:

- 期待集合: q10「血圧」・q14「血圧測定」→ {at0004, at0005}
- 第 2 候補: q08「発症」→ expected に at0002 を足して集合にするか、順位つきにするかは人間の判断を問う
- 負例: 「臨床検査」→ forbidden ProblemList at0003（q15 の旧競合）。「既往歴」→ forbidden problem_diagnosis（q18 注記）
- 保留問の出題化: q21「既往歴 → story」（jp_referral を索引に含めると成立の見込み）、「検体 → CLUSTER.specimen」（pending、v0.3 待ち）
- aql: デモクエリ 1〜5 を問い（日本語）＋参照 AQL ＋ `demo_initial` の期待行として出題（例: 「2型糖尿病または高血圧症の記録を出所つきで」→ 3 行）

## 5. 自己承認した判断（根拠は `docs/reports/s1-eval-v2-log.md` R1）

| # | 判断 | 捨てた案 |
|---|---|---|
| D1 | v1 のゴールドは触らずアダプタで読む | v1 ファイルを v2 形式に書き換える（ゴールド本体に触る） |
| D2 | `aql` 種の採点対象は AQL 文字列。S1 では参照 AQL 自身を通す | S1 で自然言語→AQL の何かを採点する（S4 の範囲） |
| D3 | データセットは `demo_initial` 1 つ。`rake demo:reset` と同じ手順 | 評価専用の fixture を新設する（二重管理） |
| D4 | 自動追記をやめ、報告は標準出力。pin は spec | v1 と同じ自動追記（重複の実測あり） |
| D5 | `pathcards:eval` は残す | 置き換えて消す（削除＝必ず止まる） |
| D6 | 名前空間 `Evaluation`、置き場所 `app/lib/evaluation/` | `Eval`、`lib/` 直下 |

## 6. 範囲外

検索実装の改良（S3）、クエリビルダーとリンタ（S2、`docs/design/s2-query-builder-plan.md` で別に計画）、ゴールドの臨床判断、CI への rake の定期実行、コード値の条件（openehr 2.5.0 の後）。

## 7. 順位と許容（R-20261124-15 による形式の拡張）

裁定 R-20261124-15（ゴールド案の臨床レビューの結果）で、card の問いの形式に 2 つを足す。基準点は
`feat/s1-eval-v2-gold-draft` に main（openehr 2.5.0 入り）を取り込んだ `287b976`。

### 7.1 形式

```yaml
- id: c008
  kind: card
  query: "発症"
  expected:
    - { archetype_id: openEHR-EHR-EVALUATION.problem_diagnosis.v1, at_code: at0077, rank: 1 }   # 第 1 候補
    - { archetype_id: openEHR-EHR-EVALUATION.problem_diagnosis.v1, at_code: at0002, rank: 2 }   # 第 2 候補
  acceptable: []     # 許容。正解でも誤りでもなく、上位に出てよい候補（forbidden とは別）
```

- `rank` は 1 以上の整数。小さいほど上位。同じ順位を複数の要素に付けてよい
- `rank` を 1 つも持たない問い（v1 の 17 問、期待集合だけの問い）は、全要素が同じ順位として読む
- 1 問の中で `rank` のある要素と無い要素を混ぜると読み込みで止める（どちらの意味かを推測しない）
- `acceptable` は `forbidden` と同じ形（`{archetype_id, at_code}`）。hit にも負例違反にも数えない

### 7.2 指標（案。そのまま実装に進む）

| 指標 | 定義 |
|---|---|
| 順位の組 | 期待集合のうち、順位が異なる 2 要素の組（上位, 下位）の数。順位が 1 種類だけの問いは 0 |
| 守られた組 | 結果の列（top-k で切らない全体）で、上位の要素が出ていて、かつ下位の要素より先に出る（下位が出ないときも守られたと数える）組の数。上位が出ない組と、両方とも出ない組は守られていない |
| 順位遵守（問い単位） | 順位の組が 1 つ以上ある問いのうち、すべての組が守られた問いの数 ÷ 順位の組を持つ問いの数 |
| 許容の出現 | `acceptable` の要素が top-3 に出た問いの数（情報。良し悪しを付けない） |

- 既存の指標（hit@1・hit@3・recall@3・MRR・完全失敗・負例違反）の定義は変えない。hit は「期待集合のどれか」のままで、
  順位が正しいかは順位遵守で別に見る
- 要素の位置は、その要素に一致する最初のカードの位置。1 枚のカードが上位と下位の両方に一致する（位置が同じ）組は守られていない

### 7.3 捨てた案

| 案 | 捨てた理由 |
|---|---|
| hit@1 を「第 1 候補が 1 位」に定義し直す | 既存の問いの数字は変わらないが、指標の名前と意味がずれる。v1 との比較軸（Top-1）を保つ |
| nDCG（順位を利得にする） | 利得の付け方（第 2 候補を何点にするか）が臨床の判断になる。レビューで決まっていないことを足さない |
| 位置を top-3 で切る | 第 2 候補が 4 位以下のとき「出ない」と同じ扱いになり、下位が上位より先に出た逆転を見落とす |
| `rank` の無い要素を 1 と読んで混在を許す | 書き忘れと意図した同順位の区別がつかない |

### 7.4 テスト TODO

1. 読み込み: 「expected の rank と acceptable を読む」「rank が整数でない・0 以下・混在は読み込みで止まる」
2. 採点: 「第 1 候補が第 2 候補より先なら順位は守られる」「逆順・第 1 候補が出ない・両方出ないは守られない」「第 2 候補だけ出ないのは守られる」
3. 採点: 「rank の無い問いは順位の組 0（順位遵守は対象外）で、既存の指標は変わらない」
4. 採点: 「acceptable が top-3 に出ても hit にも負例違反にもならず、許容の出現に挙がる」
5. 集計と報告: 「順位遵守・許容の出現の行が出る」
6. **regression pin**: 「v1 の 17 問の集計（Top-1 14/17 ほか）は rank の導入の前後で同じ。順位の組を持つ問いは 0」
7. ゴールドの確定: fixture の反映（裁定の問いごとの結果）、v1 の q21 の削除と v1 の集計が変わらない pin

### 7.5 確定にともなう変更（実装中に決めたもの。根拠は `docs/reports/s1-eval-v2-log.md` R13・R15）

- 保留解除候補は、期待先のアーキタイプが**すべて**コーパスに現れた保留問だけにする（2.4 の「現れたら」を狭める）。
  c021 が problem_diagnosis（もとからコーパスにある）を期待に持つため
- `rake evaluation:run` は、v1 の 17 問の報告と、ゴールド v2 の報告を分けて出す（2.5）。v1 の表を確定の前後で同じに保つ
- v1 の seed の q21（draft）は v2 の c021 に移して消した（2.2 の「v1 のゴールド本体は変更しない」の例外。裁定 R-20261124-15 の明示の指示）

## 8. S2 の経路（R-20261124-21 の作業列 3）

クエリビルダー（`docs/design/s2-query-builder-plan.md` 6 節）が組んだ AQL を、参照 AQL と同じ採点器に通す。

### 8.1 形式

aql の問いに `selection`（クエリビルダーへの入力）を足せる。無い問いは、これまでどおり参照 AQL だけを採点する。

```yaml
selection:
  columns:
    - { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 }
  conditions:
    - card: { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 }
      operator: ">"          # カードの型で決まる（設計書 6.3 の表）
      value: 110             # 値集合はコードの配列、日付は {from, to}
  composition_name: false
```

- カードは `{archetype_id, at_code}` で指す（`cards` と同じ形）。索引（active のカード）で最初に当たるカードを使う。
  同じアーキタイプが複数のテンプレートにあっても、ビルダーが組む AQL は同じ形になる
- `columns` が無い、条件に `card`・`operator` が無い `selection` は、読み込みで止める

### 8.2 採点

`Evaluation::BuilderRoute.score(question)`: selection → `QueryBuilder::Builder` → リンタ → `AqlScorer.score(question, aql:)`。

| 結果 | 意味 |
|---|---|
| 一致（match） | 組んだ AQL が `expected_rows` と同じ行を返す |
| 不一致（mismatch） | 行が違う（不足・余分を出す） |
| 実行不能（unexecutable） | エンジンが実行できない |
| 組めない（unbuildable） | 索引に無いカード、ビルダーが拒む選択、リンタの error |

- 母数は、active で `selection` を持つ aql の問い。報告は「aql: S2 の経路」の節（母数が 0 なら節を出さない）
- 参照 AQL の採点（ゴールドの健全性）とは別に数える

### 8.3 ゴールドに足す問い（案。臨床のレビューは人間）

- 案は `spec/fixtures/evaluation/v2/aql_s2.yml` に `status: draft` で置く（a006〜a008）。確定した 11 問は変えない
- 確定した a001〜a005 に `selection` を足すかどうかは、ゲート報告で問う（足す YAML の案は `docs/reports/s2-query-builder-log.md` R15）
- 案の健全性（参照 AQL と S2 の経路の両方が期待行に一致）は spec で固定する

### 8.4 selection に書ける条件を足す（R-20261125-6）

クエリビルダーに足した 3 つの条件（`docs/design/s2-query-builder-plan.md` 7 節）を、`selection` でも書けるようにする。

```yaml
conditions:
  - card: { archetype_id: openEHR-EHR-EVALUATION.problem_diagnosis.v1, at_code: at0073 }
    operator: MATCHES
    value: [at0076]
    include_missing: true        # 未記入を含む（値集合の条件だけ）
  - card: { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 }
    operator: OUTSIDE            # 範囲の外
    value: { low: 90, high: 140 }
  - any:                         # どちらかを満たす
      - { card: { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0004 }, operator: ">=", value: 140 }
      - { card: { archetype_id: openEHR-EHR-OBSERVATION.blood_pressure.v2, at_code: at0005 }, operator: ">=", value: 90 }
```

- 読み込みで止めるもの: `any` が配列でない、`any` の中の条件に `card`・`operator` が無い
- 値の中身（下限 > 上限、値集合でない項目への未記入 など）は読み込みでは見ない。ビルダーが拒み、採点は「組めない」になる（8.2）
- いまのゴールドと案（a001〜a008）は、この形を使っていない。使う問いは、サンプルデータが増えたあとの問いの案で出す

## 9. 負例だけの問い（R-20261125-7 による形式の拡張）

状態: 計画を追記して、そのまま実装に進む（R-20261125-7）。基準点: anlage main `db588b8`。

### 9.1 ねらい

「何も出ないのが正解」の問いを採点する。問いの語が、あるカードに着地してはいけないこと（例: 「肥満度」が BMI のカードに着く）を測る。
いまの形式は、期待（`expected`）が空の問いを完全失敗に数えてしまう。

### 9.2 形式

card の問いで、`expected` が空の配列、`forbidden` が 1 つ以上のものを「負例だけの問い」と読む。新しいキーは足さない。

```yaml
- id: c0xx
  kind: card
  query: "…"
  expected: []
  forbidden:
    - { archetype_id: openEHR-EHR-OBSERVATION.body_mass_index.v2 }   # at_code を省くと、そのアーキタイプのどのカードも負例
  match: card
```

- `expected` も `forbidden` も空の card の問いは、読み込みで止める（採点できるものが無い。黙って母数を変えない）
- 負例の照合は、これまでの `forbidden` と同じ（`match: card` で at_code が無ければアーキタイプの一致）
- status（active／draft／pending）の意味は変えない

### 9.3 採点と集計

- 負例だけの問いは、**card の集計（Top-1・Top-3・完全失敗・MRR・recall@3・負例違反・順位遵守・許容の出現）の母数に入れない**。
  期待が無いので、hit も完全失敗も定義できない
- 別に数える: 負例だけの問いの数と、負例が上位（top-3）に出た問いの数。`Run#negative_summary` → `{ questions:, violations: }`
- 既存の「負例違反」（期待を持つ問いの top-3 に負例が出た数）は、そのまま

### 9.4 報告

- 節「## card: 負例だけの問い（N 問）」を card の節のあとに出す。行は「負例が上位（top-3）に出た問い x/N」と、その一覧（問い、出た負例、順位）
- 負例だけの問いが 1 つも無ければ、節を出さない（既存の報告は 1 字も変わらない）

### 9.5 既存の問いの採点結果が変わらないこと（regression pin）

- 負例だけの問いを混ぜて走らせても、`card_summary` がもとの問いだけのときと同じであることを spec で固定する
- v1 の 17 問、ゴールド v2 の数字の pin（`runner_spec`・`evaluation_run_spec`・`pathcards_eval_spec`）は、この変更で触らない

### 9.6 テスト TODO

1. 読み込み: `expected: []` と `forbidden` の問いを読める。両方が空なら止まる
2. `Question#negative_only?`
3. 実行: 負例だけの問いは `card_results` に入らず `negative_results` に入る。混ぜても `card_summary` は同じ
4. 集計: `negative_summary`（負例が top-3 に出た数。4 位以下なら違反にしない。何も当たらなければ違反なし）
5. 報告: 節が出る／問いが無ければ出ない
