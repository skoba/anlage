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
