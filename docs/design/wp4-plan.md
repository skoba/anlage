# WP4 実装計画: 検索評価ハーネス

**作成日**: 2026-08-24
**対象Issue**: `skoba/anlage#14`（goal）
**位置づけ**: `claude-code-prompt_semantic-pathcards.md` 4節WP4。WP3（パスカード索引・検索層、`skoba/anlage#12`、完了済み）の精度を定量評価する。
**ログ**: `docs/reports/wp4-log.md`（R1〜。本計画のexplore実測記録）

> **本文書はexplore→planのみの成果物**。WP4自体の実装（コード変更）は
> 本タスクでは行わない。承認後、別タスクとして着手する。

## Step 1 explore実測結果（要約。詳細は`docs/reports/wp4-log.md` R1）

### 原文プロンプトとの解釈のずれ（承認事項1で扱う）

`claude-code-prompt_semantic-pathcards.md` WP4節原文は「日本語臨床記述→**正解アーキタイプ**（可能ならパスまで）」「指標は**top-1 / top-3精度**」と、1問=1正解archetypeの**単一ラベル評価**を明記している。一方、本タスクの指示文（Step 1-1「正解**カード集合**」、Step 1-2「Recall@k / MRR」）は、1問に複数の正解がありうる**集合ベースの情報検索評価**を示唆しており、両者にずれがある。1問1正解の場合はtop-k精度とRecall@kが同義になるため実害は小さいが、将来複数正解を許す設問を設計するかどうかで評価データの形式が変わる。

### 実測4点

1. **CIはrspec/rakeを一切実行していない**（`.github/workflows/ci.yml`はbrakeman・bundler-audit・importmap auditのみ、WP3探索時の発見の再確認）。「CIで実行可能にする」を字義通り満たすには新規CIジョブ追加が要り、これはWP4単体のスコープを超えうる。
2. **評価データの母数は7archetype**（現有4テンプレート・15カードから実測棚卸し）。シード20問は必然的に同一archetypeを異なる言い回しで問う設問が多くなる（実物主義上、archetype多様化にはOPT追加供給が必要）。
3. **WP3の18クエリは部分再利用のみ可能**（`docs/reports/wp3-log.md` R1はカテゴリ集計のみで、個々のクエリ×正解×結果を保持した構造化データは無い。名指しで復元できるのは7-8問相当）。
4. **検索サービスの出力はtop-k判定・MRR算出に直接使える**（`Opt::PathcardSearch.call(query)`が`identity.archetype_id`込みのスコア降順配列を返す）。既存rakeタスク（`lib/tasks/pathcards.rake`の`pathcards:backfill`）が`pathcards:eval`追加の直接の先例になる。

## Step 2 計画

### 評価データ設計

- **形式**: `spec/fixtures/pathcards_eval_seed.yml`（新設）。1エントリ = `{id, query, expected_archetype_id, expected_at_code (optional), notes}`。`expected_archetype_id`は必ず現有fixtureに実在するarchetype_id（実物主義）。
- **初期データ**: 20問。内訳の目安 — WP3から復元可能な7-8問（「収縮期」「収縮期血圧」「拡張期血圧」「身長体重」「BMI」「体格指数」「既往」「疑い」相当、既に成立/不成立が実測済み）＋新規12-13問（現有7archetypeの範囲内で、単純一致・粒度ギャップ・同義語ギャップの3カテゴリをバランスよく配分）。
- **拡充前提**: コミュニティで100問へ拡充される前提（原文どおり）。フラットなYAMLリストのため追記が容易。

### 指標選定

- **主指標（デモで語れる数字）**: top-1精度・top-3精度（原文どおり）、完全失敗率（0-hit——正解archetypeが結果に一切現れない問題の割合。WP3の「BMI」のような同義語ギャップを可視化する）
- **副指標（Phase 2判断に効く数字）**: MRR（Mean Reciprocal Rank。正解が何位に出たかを連続値で捉え、Phase 1→Phase 2の微小な改善を追跡できる）。WP3の失敗類型（粒度ギャップ／同義語ギャップ／フィールド範囲）別の内訳集計も付与し、「どの種類の失敗が残っているか」をPhase 2設計に直接フィードバックできる形にする。

### ハーネスの置き場・実行方式

- `lib/tasks/pathcards.rake`に`pathcards:eval`タスクを追加（既存`pathcards:backfill`と同じ`namespace :pathcards`直下）。
- **CI実行はWP4のスコープに含めない**（承認事項2）。現行CIがrspec/rakeを一切実行していないため、これを変えるのは別の大きな決定であり、DoD「`rake pathcards:eval`一発でスコアが表示される」は手動実行で満たす。CI組み込みは別Issueとして切り出す。

### Phase 2比較の拡張性

- 評価データファイル（YAML）はPhase 1/2共通で使い回す。
- 実行結果は`docs/reports/wp4-eval-log.md`（新設）に追記形式で記録する。1回の実行ごとに「実行日時・検索実装のタグ（`phase1-bigram`等）・top-1/top-3精度・完全失敗率・MRR・失敗類型内訳」を1エントリとして残し、Phase 2実装後に同じ形式で追記すればbefore/after比較が文書上そのまま並ぶ。

### TDD方針（実装着手後）

1. Red: `pathcards_eval_seed.yml`の構造（全エントリが`id/query/expected_archetype_id`を持つ、`expected_archetype_id`が実在するarchetype_idの集合に含まれる）を検証するspec
2. Red/Green: `pathcards:eval`タスク本体（既知の小さな評価データセットで、期待どおりのtop-1/top-3/MRR/完全失敗率が算出されることを検証）
3. 20問ドラフトの人間レビュー（承認事項3）を経てから最終データを確定

### 承認が必要な判断

1. **評価の粒度**: 単一正解archetype＋top-1/3精度（原文どおり、推奨）か、複数正解許容の集合ベースRecall@k/MRR（本タスク指示文の解釈）か。**推奨: 原文どおりの単一ラベル評価**（シンプルで原文の明示的指定に忠実、複数正解の必要性は現時点で実証されていないためYAGNI）
2. **CI実行はWP4のスコープに含めない**（現行CIがrspec自体を回していないため、新規CIジョブ追加は別Issueとして切り出す）
3. **評価データの人間レビュー範囲**: Claude Codeが20問ドラフト（WP3流用7-8問＋新規12-13問、現有7archetype範囲内）を提案し、正解archetype_idの正確性・クエリ文言の臨床的妥当性を人間が確認してから確定する、という運用でよいか
4. **評価データの保存場所**: `spec/fixtures/pathcards_eval_seed.yml`（推奨。既存fixture配置慣行に最も近い）

## Verification（実装着手後）

- `bundle exec rspec`（新規specファイル含む）が全件green
- `rake pathcards:eval`を実行し、top-1/top-3精度・完全失敗率・MRRが表示されることを確認
- `docs/reports/wp4-eval-log.md`に初回実行結果が記録されることを確認
- Issue #14のAcceptance criteria（plan確定後に追記予定のもの）すべてにチェックが入る状態であることを確認
