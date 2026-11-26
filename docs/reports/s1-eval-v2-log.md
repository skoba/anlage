# S1（評価 v2）の進行ログ

裁定: R-20261124-11（作業列 1〜3）、R-20261124-8。計画: `docs/design/s1-eval-v2-plan.md`。
レーン: anlage（引く側）。worktree `/home/skoba/src/anlage-worktrees/s1-eval-v2`。

## R1 着手と探索（2026-11-24）

- 台帳: R-20261124-11 の行を 発行 → 着手 に更新（anlage-ops `ace8e6e`）
- 基準点: anlage main `6c100e0`（PR #78 で書く側が `CLAUDE.md`「全開の進め方」を先に入れた。
  私が同じ節を書いたブランチ `docs/full-speed-claude-md`〔`8452819`〕は重複になったので PR は開かない。
  ブランチと worktree `full-speed-claude-md` の削除はゲート対象として報告に回す）
- **Issue の起票は実行環境の権限で止められた**（`gh issue create` が拒否）。Issue 案は本ログ末尾。起票は人間に回す。
  それまでブランチ名に Issue 番号を含めない（`docs/s1-eval-v2-plan`、`feat/s1-eval-v2`）

### 実測（計画書 1 節の根拠）

- `lib/tasks/pathcards.rake:11-30`: rank は `identity.archetype_id` の一致のみ。`expected_at_code` は不使用
- `docs/reports/wp4-eval-log.md`: 2026-08-26 に `13:21:08Z`／`13:25:43Z`／`13:28:38Z` の同一値 3 件（自動追記の雑音）
- `spec/lib/tasks/pathcards_eval_spec.rb:63-77`: 17 問の pin（Top-1 14/17、Top-3 15/17、完全失敗 2/17、MRR 0.8529、11/11・4/4・0/2）
- `spec/fixtures/pathcards_eval_seed.yml` q10・q14 の notes に「期待集合 {at0004, at0005} の第 1 号」、q08 に第 2 候補 at0002、
  q15 に ProblemList at0003 との偽陽性、q18 に「既往歴の約 8 割は story 系」、q19（コメントアウト）に「検体 → CLUSTER.specimen」
- `openehr-rails-0.8.0/lib/openehr_rails/aql/executor.rb`: `Executor.execute(aql, params:, ehr_scope:, composition_scope:)`。
  `InvalidQuery`／`UnsupportedFeature` に写す。`openehr-2.4.3/lib/openehr/aql/result_set.rb`: `columns`・`rows`・`to_json`
- `spec/demo/cross_template_query_spec.rb:20-23`: spec の中で `Rake::Task["demo:reset"].invoke` して初期状態を作っている
- `config/database.yml` test: `storage/test.sqlite3`（worktree ごとに別。書く側と並行して rspec を回せる）
- `app/lib/opt/pathcard_search.rb`: bigram の積集合の大きさがスコア。`Template.active` のカードのみ

### 自己承認した判断

計画書 5 節 D1〜D6。根拠は上の実測。D4（自動追記をやめる）は v1 の挙動の変更だが、`pathcards:eval` 自体は変えないので
利用者に見える結果は変わらない。

### Issue 案（起票は人間。goal ラベル）

タイトル: `[goal] S1 評価 v2: 正解をカードから AQL の結果へ広げる（期待集合・負例・保留問）`

Acceptance criteria:

1. 計画書 `docs/design/s1-eval-v2-plan.md` が main に入る
2. 評価 v2 の枠組み（`card`／`aql` の 2 種、`draft`／`pending`、期待集合と負例、実行、採点、Markdown 報告、`rake evaluation:run`）が main に入る
3. v1 の 17 問を v2 で読み、Top-1 14/17・Top-3 15/17・完全失敗 2/17・MRR 0.8529 を再現する spec が green。v1 のゴールド本体は変更しない
4. `aql` 種の問いが `demo_initial` の上で参照 AQL を実行し、期待行と照合できる（spec で固定）
5. 保留問は母数から外れ、期待先がコーパスに現れたら「保留解除候補」として報告に出る
6. ゴールド v2 の案を `draft` で置いてゲート報告（臨床のレビューは人間。R-20261124-11 作業列 3）

Out of scope: 検索実装の改良（S3）、クエリビルダーとリンタ（S2）、ゴールドの臨床判断、CI への rake の定期実行。

## R2 サイクル 1: v1 シードのアダプタ読み込み（2026-11-24）

- Red: `spec/lib/evaluation/questions_spec.rb` → `NameError: uninitialized constant Evaluation`（読み込み時エラー、0 examples）
- Green: `app/lib/evaluation/question.rb`（1 問の値オブジェクト。kind／status／match）、
  `app/lib/evaluation/questions.rb`（`from_v1_seed`。draft → status: draft、expected は 1 要素、match: archetype）。2 examples, 0 failures
- 実測: v1 の seed は active 17・draft 1（q21）。q10 の expected_at_code は空（nil に写す）

## R3 サイクル 2: v2 YAML の読み込みと形式の検査（2026-11-24）

- Red: `NoMethodError: undefined method 'from_v2' for module Evaluation::Questions`（4 examples, 2 failures）
- Green: `Questions.from_v2(dir)`。ファイル名順に `*.yml` を読む。kind ごとの必須キー（card: query・expected／aql: query・dataset・reference_aql・expected_rows）、
  未知の kind・status・match は `InvalidQuestion` で止める（黙って母数を変えない）。4 examples, 0 failures

## R4 サイクル 3: card の採点器（2026-11-24）

- Red: `NameError: uninitialized constant Evaluation::CardScorer`
- Green: `app/lib/evaluation/card_scorer.rb`。rank（期待集合のどれかが最初に出た 0 始まりの順位）、hit@1・hit@3、recall@3（集合）、逆順位、完全失敗、
  負例違反（forbidden が top-3 に出る）。match: archetype は at_code を見ない（v1 互換）。9 examples, 0 failures（questions_spec と合わせて）

## R5 サイクル 4: 実行器と最初の pin（2026-11-24）

- Red: `NameError: uninitialized constant Evaluation::Runner`
- Green: `app/lib/evaluation/runner.rb`。active の card の問いを `Opt::PathcardSearch` で引いて `CardScorer` で採点、draft／pending は一覧に残す。
  `Run#card_summary` が questions・hit_at_1・hit_at_3・complete_failures・mrr・recall_at_3・violations・by_intent を返す
- **pin の実測**（4 テンプレートを索引、v1 の 17 問をアダプタで読む）: Top-1 14/17、Top-3 15/17、完全失敗 2/17（q16・q18）、MRR 0.8529、
  intent_tag 別 11/11・4/4・0/2 ── `spec/lib/tasks/pathcards_eval_spec.rb` と同じ数字。2 examples, 0 failures

## R6 サイクル 5: aql の採点器とデータセット demo_initial（2026-11-24）

- Red: `NameError: uninitialized constant Evaluation::AqlScorer`
- Green: `app/lib/evaluation/datasets.rb`（`demo_initial` は `rake demo:reset` を呼ぶ。手順を写さない）、
  `app/lib/evaluation/aql_scorer.rb`（`OpenehrRails::Aql::Executor` で実行、行を多重集合で比較、`ordered: true` で順序も。
  `OpenehrRails::Aql::Error` は unexecutable に数える。採点対象の AQL は `aql:` で差し替え可）
- 実測（demo_initial）: 収縮期 > 110 → `[[120.0]]`。横断の傷病名 → 3 行（順序を入れ替えても match、ordered なら mismatch）。
  `value/defining_code/code_string` → `UnsupportedFeature: unsupported path attribute "defining_code" …`（上流候補 10 項の再現）。5 examples, 0 failures

## R7 サイクル 6: 実行器の aql と保留問（2026-11-24）

- Red: `NoMethodError: undefined method 'aql_results'`／`'releasable_pendings' for an instance of Evaluation::Runner::Run`
- Green: dataset ごとに 1 回 `Datasets.build` してから aql を採点（`aql_summary`: match／mismatch／unexecutable）。
  `releasable_pendings` は期待先のアーキタイプが active のカードに現れた保留問
- 実測: demo_initial（jp_referral を含まない）では story の保留問は候補に出ず、jp_referral を索引すると c021 だけが候補になる。18 examples, 0 failures

## R8 サイクル 7: Markdown 報告（2026-11-24）

- Red: `NameError: uninitialized constant Evaluation::Report`
- Green: `app/lib/evaluation/report.rb`。`Report.render(run, label:)` が card の集計表と intent_tag 別、完全失敗、負例違反、aql の集計と不一致の差分、
  draft、保留問（解除候補に印）を Markdown で返す。ファイルには書かない。3 examples, 0 failures
- spec の修正: 保留問 c19 の期待先を specimen にした（補助メソッドの既定が blood_pressure で、コーパスに有るため解除候補になってしまう誤り）

## R9 サイクル 8: rake evaluation:run（2026-11-24）

- Red: `RuntimeError: Don't know how to build task 'evaluation:run'`
- Green: `lib/tasks/evaluation.rake`。v1（アダプタ）＋ v2（`spec/fixtures/evaluation/v2/`）の問いを走らせ、Markdown を標準出力に出す。
  `RESET=1` のときだけ aql を採点（dataset を作り直して dev DB の記録を入れ替えるため。既定は飛ばして件数を出す）。
  spec は `docs/reports/` の mtime が変わらないことも固定。2 examples, 0 failures

## R10 サイクル 9: 17 問を match: card でも集計（情報）（2026-11-24）

- Red: `evaluation_run_spec` の 3 例目（「# 評価 v2（phase1-bigram、match: card）」が出ない）1 failure
- Green: `Questions.from_v1_seed(match: :card)`、rake が 2 本目の報告を出す。7 examples, 0 failures
- 実測（demo_initial の 5 テンプレートを索引、at_code まで見る）: Top-1 14/17、Top-3 15/17、完全失敗 2/17、MRR 0.8431、recall@3 0.8824。
  archetype 一致との差は q07「検査結果」だけ（archetype なら rank 1、at0001 まで見ると rank 2。analyte の他のカードが先に出る）
- 全 suite（worktree、SQLite）: 267 examples, 0 failures, 3 pending（pending は既存の jp_referral 統合 spec）

## R11 ゲート報告: ゴールド v2 の案（作業列 3。ここで止まる）（2026-11-24）

**判断を求めること**: `spec/fixtures/evaluation/v2/cards.yml`（6 問）と `aql.yml`（5 問）の案を、臨床のレビューで確定してよいか。
確定の操作は、各問の `status: draft` を外し（pending はそのまま）、`reviewed_by`／`reviewed_at` を記入すること。
ゴールド本体は人間の専有領域なので、セッションは案を出すところまで（v1 の seed は変更していない）。

### 案の一覧と実測（demo_initial の 5 テンプレートを索引、案を active と見なして採点。情報）

| id | 種 | 問い | 形 | いまの実測 |
|---|---|---|---|---|
| c010 | card | 血圧 | 期待集合 {bp at0004, at0005} | rank 0、recall@3 1.0（両方が 1・2 位） |
| c014 | card | 血圧測定 | 期待集合 {bp at0004, at0005} | rank 0、recall@3 1.0 |
| c008 | card | 発症 | 期待集合 {pd at0077, at0002} | rank 0、recall@3 0.5（at0002 は top-3 に無い） |
| c015 | card | 臨床検査 | 期待 lab_result（archetype）、負例 pd at0003 | rank 0、負例違反なし（旧競合は container_labels の導入後に消えている。推論） |
| c021 | card（pending） | 既往歴 | 期待 story at0004、負例 pd | コーパスに story 無し。jp_referral を索引すると解除候補になる（R7 で実測） |
| c019 | card（pending） | 検体 | 期待 CLUSTER.specimen、負例 lab_result | コーパスに specimen 無し。負例 lab_result が 1 位（誤着地の実例） |
| a001 | aql | 収縮期血圧が 110 mmHg を超える記録 | 数値比較 | 一致 `[[120.0]]` |
| a002 | aql | 診断確度が「疑い」の傷病名 | 値集合（表示文字列で仮置き） | 一致 `[["高血圧症"], ["2型糖尿病"]]` |
| a003 | aql | 2型糖尿病または高血圧症の記録を出所つきで | 横断 | 一致 3 行（デモクエリ 5 と同じ） |
| a004 | aql | 空腹時血糖の値 | 文字列一致 ＋ 埋め込み CLUSTER | 一致 `[[98.0]]` |
| a005 | aql | 身長が 170 cm 以上の記録 | 境界値を含む数値比較 | 一致 `[[170.0]]` |

### 人間に問うこと（案の notes にも書いた）

1. c008: 集合（順序なし）でよいか、at0077 主・at0002 第 2 候補の順位つきが要るか（順位つきなら形式の拡張を別に計画）
2. c015: 2026-08-25 のレビュー（臨床検査 → laboratory_test_result の単一固定は恣意）と、期待を archetype 一致に置く案が両立するか。
   両立しないなら「負例だけの問い（expected 空）」を形式に足すか
3. c021: 確定時に v1 の q21（draft）と二重にしない扱い（v1 に残す／v2 に移す）
4. a002: コード値（at0074）の本来形は openehr 2.5.0 のあと。それまで表示文字列「疑い」の一致で仮置きしてよいか（R-20261124-11 の 5 のとおり）

### 保留問の運用

- pending の 2 問は母数に入らない。`rake evaluation:run` の報告で、期待先がコーパスに現れると「保留解除候補」の印が付く（c021 は jp_referral の登録で付く）

### PR

- 計画書: PR #81（CI run 45389992419 green。マージは実行環境の権限で止められたので人間に回す）
- 枠組み: PR #84（`feat/s1-eval-v2`、#81 の上）
- ゴールド案: 本ログの R11 と同じ PR（`feat/s1-eval-v2-gold-draft`、#84 の上）。**人間のレビューが済むまでマージしない**

## R12 裁定 R-20261124-15 の着手、main の取り込み、確定前の実測（2026-11-24）

- 裁定 R-20261124-15（ゴールド案の臨床レビューの結果）を台帳で読み、自分宛ての行を 着手 にした（anlage-ops `16e0332`）
- worktree `s1-eval-v2`（ブランチ `feat/s1-eval-v2-gold-draft`、`a6f3a86`、未コミット物なし）で再開した。裁定が対象のブランチと SHA を
  名指ししているので、同じ slug の worktree の再開にあたる（作業ツリー規律の例外の条件）
- main（`5ad061b`、openehr 2.5.0 入り）を merge で取り込んだ（`287b976`。rebase はしない＝履歴を書き換えない）
- 取り込み直後の Red（実測）: `aql_scorer_spec` の「defining_code への終端ホップは unexecutable」が 1 failure。
  openehr 2.5.0 でコード値に届くようになったため。実行不能の例を `archetype_details`（上流候補 25 項。いまも
  `UnsupportedFeature: unsupported path attribute "archetype_details"`）に替え、コード値の条件の一致を pin にした（`d23c530`）
- a002 の本来形の実測（demo_initial、`bin/rails runner`）:
  `WHERE ev/data[at0001]/items[at0073]/value/defining_code/code_string MATCHES {"at0074"}` → `[["高血圧症"], ["2型糖尿病"]]`
  （`= 'at0074'` でも同じ 2 行。診断確度の無い 2型糖尿病 1 件は入らない）
- **確定前の採点**（`RESET=1 bundle exec rake evaluation:run`、`287b976`）: card 17 問（v1 のみ）Top-1 14/17、Top-3 15/17、
  完全失敗 2/17、MRR 0.8529、recall@3 0.8824、負例違反 0/17。aql 0 問。draft 10 問（q21 と案の 9 問）、保留問 2 問

## R13 自己承認した判断（R-20261124-15 の範囲内。計画書 7 節）

| # | 判断 | 根拠・捨てた案 |
|---|---|---|
| E1 | 順位の指標は「順位の組が守られたか」（問い単位の順位遵守と、組の数）。位置は top-k で切らない | 裁定「指標の案は計画書に書いて、そのまま進む」。捨てた案（hit@1 の定義変更、nDCG、top-3 で切る）は計画書 7.3 |
| E2 | rank の無い要素には rank を付けずに読み、採点器が同じ順位として扱う。1 問の中の混在は読み込みで止める | 既存の spec の期待値（`expected` の等値）が変わらない。書き忘れと同順位を推測で区別しない |
| E3 | 許容（acceptable）は hit にも負例違反にも数えず、top-3 に出た問いを「許容の出現」として情報に出す | 裁定「正解でも誤りでもなく、上位に出てよい候補」 |
| E4 | c015 の acceptable は空（ID を足さない）。種類は notes に書く | 裁定「いまのコーパスには無いので notes に種類を書く」。コーパスの実測でも検査結果のアーキタイプは laboratory_test_result だけ |
| E5 | 保留解除候補は、期待先のアーキタイプが**すべて**コーパスに現れたときだけ（もとは「どれか」） | c021 が problem_diagnosis を期待に持つと、story が無いのに解除候補の印が付いた（実測。R15）。裁定「pending の条件はそのまま」 |
| E6 | `rake evaluation:run` は v1 の 17 問とゴールド v2 を別の報告に出す（もとは 1 つの表） | 確定で v2 の card が母数に入ると表が 21 問になり、v1 の 17 問の数字が見えなくなる。裁定「v1 の採点結果が変わらないことを pin」 |
| E7 | a002 は `MATCHES {"at0074"}` の形（`=` でなく） | 問いの notes が S2 の条件型「値集合」を指している。実測は両方とも同じ 2 行（R12） |
| E8 | a002 は draft を外して確定 | 裁定の条件「2.5.0 への版上げが main に入ってから」は満たされている（PR #92 → main `94561e9`） |

## R14 サイクル: 順位と許容（読み込み → 採点 → 集計と報告）

- 計画: `docs/design/s1-eval-v2-plan.md` 7 節（`2de15ad`）
- サイクル 1（読み込み、`419bab1`）
  - Red: `questions_spec` 2 failures（`expected` に rank が無い、`rank: 0` で `nothing was raised`）
  - Green: `Question#acceptable`、`Questions.ranked_refs`。24 examples, 0 failures
- サイクル 2（採点、`587aa7c`）
  - Red: `card_scorer_spec` 12 examples, 7 failures（`undefined method 'acceptables' for an instance of Evaluation::CardScorer::Score` ほか）
  - Green: `Score` に `order_pairs`・`order_pairs_kept`・`order_kept`・`acceptables`。31 examples, 0 failures
- サイクル 3（集計と報告、v1 の regression pin、`e537ba1`）
  - Red: `report_spec` 2 failures（「順位遵守」の行が無い）、`runner_spec` 1 failure（`card_summary` に `ranked_questions` が無い）
  - Green: `card_summary` に 5 項目、報告に 2 行と 2 つの一覧。43 examples, 0 failures
  - **pin**: v1 の 17 問は Top-1 14/17、Top-3 15/17、完全失敗 2/17、MRR 0.8529、recall@3 0.8824 のまま。順位の組を持つ問いは 0

## R15 サイクル: ゴールドの確定（fixture の反映、v1 の q21 の削除、`7d28cf8`）

- Red: `questions_spec` 11 examples, 6 failures（v1 に q21 が残る、v2 に draft が残る、c008・c015・c021・a002 が案のまま）
- fixture の反映（裁定の「問いごとの結果」のとおり）
  - c008: at0077 が rank 1、at0002 が rank 2
  - c015: laboratory_test_result（archetype 一致、rank 1）、acceptable は空、forbidden は problem_diagnosis at0003。notes に広い語としての扱いと種類
  - c021: story at0004 と problem_diagnosis（archetype 一致）がともに rank 1。forbidden を外す。notes に 2 通りの記録のしかたと割合の目安。pending のまま
  - a002: コード値 at0074 の一致に書き換え
  - c010・c014・c019・a001・a003・a004・a005: 案のまま
  - 全 11 問に `reviewed_by: Kobayashi, Shinji`、`reviewed_at: 2026-11-24`。draft を外す（c019・c021 は pending のまま）
  - v1 の seed（`spec/fixtures/pathcards_eval_seed.yml`）から q21 とその前置きのコメントを消した（裁定の明示の指示）
- 反映のあとの Red（spec の追随と、見つけた 2 点）: `runner_spec`・`evaluation_run_spec`・`pathcards_eval_spec` で 3 failures（q21 を前提にした期待値）。
  追随のあと 4 failures:
  - 保留解除候補（E5）: demo_initial で c021 に「保留解除候補」の印が付いた（problem_diagnosis がコーパスにあるため）
  - rake の報告（E6）: v1 と v2 が 1 つの表（21 問）になった
- Green: `releasable_pendings` を「すべて現れたとき」に、rake を 2 つの報告に。評価の spec 53 examples, 0 failures
- 全 suite（worktree、SQLite）: 333 examples, 0 failures, 2 pending

### 確定後の採点（実測）

| 索引 | card | aql | 保留問 |
|---|---|---|---|
| demo_initial の 5 テンプレート（`RESET=1 bundle exec rake evaluation:run`） | 4 問: Top-1 4/4、Top-3 4/4、完全失敗 0/4、MRR 1.0000、recall@3 0.8750、負例違反 0/4、順位遵守 1/1（組 1/1）、許容の出現 0/4 | 5 問: 一致 5/5 | c019・c021（解除候補なし） |
| 4 テンプレート（`evaluation_run_spec` の索引。patient_blood_pressure 無し） | 4 問: Top-1 3/4、Top-3 4/4、負例違反 1/4（c015）、順位遵守 1/1 | （RESET 無しでは採点しない） | 同じ |

- v1 の 17 問は確定の前後で同じ（Top-1 14/17、Top-3 15/17、完全失敗 2/17、MRR 0.8529、recall@3 0.8824）。draft は 10 問 → 0 問
- recall@3 が 0.875 なのは c008: 第 2 候補の at0002 が結果の列に出ない（「発症」の結果は at0077 の 1 枚だけ）。順位の組は守られた扱い（上位が出て、下位が出ない）
- **c015 はコーパスで結果が変わる**（実測）: 4 テンプレートでは 1 位が負例の ProblemList at0003、2 位が laboratory_test_result at0005。
  5 テンプレートでは 1 位が laboratory_test_result at0005、at0003 は 4 位（top-3 の外）。5 つ目の patient_blood_pressure が入ると
  順位が入れ替わる理由は調べていない（推論: bigram の重みがコーパスの文書数で変わる）。負例は偽陽性を現に捕まえている

### レビューで決まっていないこと（推測で足していない）

- c015 の許容に入れるアーキタイプの ID（心電図、呼吸機能、認知機能検査など）。コーパスに入ったら人間のレビューを経て足す
- c021 を出題化する時期（pending の条件は jp_referral が demo_initial の索引に入ること）

## R16 訂正: c015 の結果が索引で変わる原因（2026-11-24、R-20261124-21 の作業列 4）

- R15 の推論（「bigram の重みがコーパスの文書数で変わる」）は誤り。実測: 「臨床検査」に当たる 4 枚は**すべて score 1 の同点**で、
  並びはテンプレートの登録順で決まる（`Opt::PathcardSearch` は同点の順序を決めていない）
- 同じ 4 テンプレートでも、LabResultReport を先に登録すると 1 位は laboratory_test_result at0005 になり、負例 at0003 は 4 位に落ちる
- 詳細と表は `docs/design/s3-search-plan.md` 2.1。Issue は `skoba/anlage#122`
- c008「発症」の第 2 候補 at0002 が出ない原因も同 2.2（カードの文に「発症」が無い。字面では届かない）


## R17 負例だけの問いの形式（2026-11-25、R-20261125-7。計画書 9 節）

- 基準点: anlage main `db588b8`。計画書に 9 節を足して push し（`9a1d1b8`）、そのまま実装した（`e2d1d82`）
- **自己承認した判断**（R-20261125-7 の範囲内）

  | # | 判断 | 捨てた案 |
  |---|---|---|
  | N1 | 新しいキーを足さず、「expected が空で forbidden がある card の問い」を負例だけの問いと読む | `kind: negative` や `negative_only: true`（書くところが 2 つになり、食い違える） |
  | N2 | 負例だけの問いは card の集計（Top-1 など）の母数に入れず、`negative_results` に分ける | 母数に入れて「負例が出なければ hit」と数える（Top-1 の意味が変わり、既存の数字と比べられなくなる） |
  | N3 | 問いが無ければ報告の節を出さない | いつも「0 問」の節を出す（既存の報告と spec の文字列が変わる） |
  | N4 | expected も forbidden も空の card の問いは読み込みで止める | 黙って完全失敗に数える（いまの挙動。母数が気づかずに変わる） |

- Red（`bundle exec rspec spec/lib/evaluation`。66 examples, 7 failures）:

  ```
  1) Questions.from_v2 expected が空で forbidden を持つ card の問いは、負例だけの問いとして読む …   （negative_only? に応えない）
  2) Questions.from_v2 expected も forbidden も空の card の問いは読み込みで止まる
       expected Evaluation::Questions::InvalidQuestion with message matching /n2.*expected.*forbidden/ but nothing was raised
  3) Report 負例だけの問いの節 …                                   ArgumentError（negative_results:）
  4) Runner 負例だけの問い regression pin: 負例だけの問いを混ぜても、card の集計と問いごとの結果は、もとの 17 問だけのときと同じ
       expected: {… questions: 17, … recall_at_3: 0.8823529411764706, violations: 0}
            got: {… questions: 20, … recall_at_3: 0.75, violations: 1}
  5)〜7) Runner 負例だけの問い …                                   NoMethodError（negative_results、negative_summary）
  ```

  4) が、いまの形式の弱点の実物（負例だけの問いを足すと、既存の集計が変わる）
- Green: `Question#negative_only?`、`Questions.build_v2` の検査、`Runner`（分けて採点）、`Run#negative_summary`、`Report.negative_section`。
  `spec/lib/evaluation` と `spec/lib/tasks` で 76 examples, 0 failures
- regression pin: 負例だけの問い 3 問（BMI判定・診断・脈拍）を v1 の 17 問に混ぜても、`card_summary` と問いごとの `Score` が 17 問だけのときと同じ（`runner_spec`）。
  v1 とゴールド v2 の数字の pin は触っていない
- ゴールド（`spec/fixtures/evaluation/v2/`）は、この PR では変えていない

## R18 card の問いを足す（2026-11-25、R-20261125-7。ゴールドの確定は人間のマージ）

- 反映: `spec/fixtures/evaluation/v2/cards.yml` に、採用の 9 問（c022・c023・c024・c026・c027・c029・c030・c031・c032、active）と、
  保留の c033（pending）を足した。`reviewed_by: Kobayashi, Shinji`、`reviewed_at: 2026-11-25`。見送りの c025・c028 は足していない
- 案: 負例だけの問い c034「肥満度」（draft。負例は body_mass_index.v2 のどのカードも）。形式は R17
- 採点（`RESET=1 bundle exec rake evaluation:run`、demo_initial の 5 テンプレート、検索は main `5eceeca`）

  | 問い | 足す前 | 足したあと |
  |---|---|---|
  | v1 の 17 問 | Top-1 15/17、Top-3 15/17、MRR 0.8824 | 同じ |
  | ゴールド v2 の card | 4 問: Top-1 4/4、Top-3 4/4、MRR 1.0000、recall@3 0.8750、負例違反 0/4、順位遵守 1/1 | 13 問: Top-1 8/13、Top-3 10/13、完全失敗 2/13、MRR 0.6987、recall@3 0.7308、負例違反 0/13、順位遵守 1/1、許容の出現 1/13 |
  | ゴールド v2 の aql 5 問 | 一致 5/5 | 同じ |
  | 負例だけの問い | — | 母数 0（c034 は draft） |

  - 足す前からの 4 問（c008・c010・c014・c015）の結果は変わらない（4 問とも 1 位。spec で固定した）
  - 1 位でない問い: c022「病名」・c023「疾患名」（0 件）、c027「診断日」（4 位）、c029「検査値」（3 位）、c030「検査項目」（2 位）
  - spec の 4 テンプレートの索引でも同じ数字（`evaluation_run_spec`）
  - これが段 D・E の before になる
- 追随した spec の pin（実測に合わせた。4 例）: `questions_spec`（問いの数と id）、`runner_spec`（card 13 問の数字、保留問と draft）、`evaluation_run_spec`（報告の文字列）
- **裁定の補足との食い違い（実測）**: 裁定は「カードの文に『最高』『最低』は無い」としているが、CardiologyEncounter のカードの説明に
  「全身の動脈血圧での最高値 …」（at0004）、「…最低値 …」（at0005）がある（`spec/fixtures/pathcards/CardiologyEncounter.golden.json`）。
  c031・c032 が 1 位に出るのは、説明の bigram（重み 1）と祖先の名前「血圧」（重み 3）による（score 5 対 4）。
  種類は裁定のとおり「同義語ギャップ」のままにし、notes に実測を書いた。種類を変えるかは統括・人間に回す
- **c033 に「保留解除候補」の印が付く**: 印は「期待先のアーキタイプがすべて索引にある」で付く。c033 の保留の理由は「日本語訳が済んでいない」で、
  heart_rate-pulse.v1 は demo_initial の索引にもうあるので、印が付いてしまう。裁定は「c019・c021 と同じ形」なので、そのとおりに足した。
  直すなら、保留の理由の種類（索引に無い／訳が無い）を形式に足す。裁定に無いので、手を付けていない
- c034 の `intent_tag`「負例のみ」は、セッションが付けた仮の名前

## R19 レビューのあとのゴールドの直し（2026-11-26、R-20261125-11）

- PR #131 は、この直しの前に人間がマージした（main `ab0dda0`）。直しは続きの PR で出す（ゴールドを変えるので、マージは人間）
- Red（先に spec の pin を書き換えた。`bundle exec rspec spec/lib/evaluation spec/lib/tasks/evaluation_run_spec.rb`、79 examples, 7 failures）:
  問いの数と id（c034 が draft のまま）、レビューの記録（c034 に無い）、c031・c032 の種類、c034 の status、draft の一覧、
  負例だけの問いの集計（母数 0）、報告の節（出ない）
- Green: `spec/fixtures/evaluation/v2/cards.yml` を裁定のとおりに直した
  - c034: `status: draft` を外して active。`reviewed_by: Kobayashi, Shinji`、`reviewed_at: 2026-11-25`。負例は body_mass_index.v2 のアーキタイプ全体
  - c031・c032: `intent_tag` を「bigram成立想定」に。notes から「種類は同義語ギャップとする…根拠としては扱わない」を外し、実測（説明に「最高値」「最低値」）を残した
  - spec の matcher の書き間違い（文字列に `exclude`）を 1 つ直して、86 examples, 0 failures
- 採点（`RESET=1 bundle exec rake evaluation:run`、demo_initial、別名表あり）

  | 問い | 直す前（main `df37baf`） | 直したあと |
  |---|---|---|
  | ゴールド v2 の card 13 問 | Top-1 10/13、Top-3 12/13、完全失敗 0/13、MRR 0.8526、recall@3 0.8846、負例違反 0/13 | 同じ |
  | 種類別（hit@3） | bigram成立想定 3/3、複合語 5/5、同義語ギャップ 4/5 | bigram成立想定 5/5、複合語 5/5、同義語ギャップ 2/3 |
  | 負例だけの問い | 母数 0（c034 は draft） | 1 問。負例が上位に出た問い 0/1（「肥満度」は 1 枚も当たらない） |

  - 「同義語ギャップ」の残り 3 問は c022「病名」・c023「疾患名」（別名表で当たる）と c027「診断日」（4 位）
  - c034 が 0/1 なのは、「肥満度」が字面でどのカードにも当たらないため。検索が BMI を避けているわけではない（段 E で言い換えを入れたときに、初めて効く問い）
