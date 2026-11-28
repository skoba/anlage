# 記録の時刻の時刻帯の進行記録（`skoba/anlage#291`。R-20261128-16 の 4）

## R1（2026-11-28）ゲート報告: 記録の時刻を、配備先の時刻帯つきで書く計画

- 種別: **ゲート報告**（利用者に見える変更で、人間が決める点を含む。裁定の 4 のとおり）
- 計画書: `docs/design/record-time-zone-plan.md`。実装は、まだしていない

### 自己承認した判断
- 無し（この PR は計画書と進行記録だけ。docs のみ）

### 実測（計画書の 1 節・3 節）
- 帳票の保存は、イベントの時刻・origin・context の start_time が、どれも `…Z`（`Time.zone` は UTC）。
  サンプルデータは、イベントの時刻と origin が `+09:00`、context の start_time が `…Z`（`Time` を gem に渡すので）
- `config.time_zone = "Asia/Tokyo"` の 1 行だけを入れた一時の worktree（`87d5f55`。openehr-rails 0.15.0）で、system を除く suite: 958 examples, 15 failures（9 ファイル）。
  一時の worktree の変更は、その 1 行だけで、commit せずに worktree ごと消した
- 15 例のうち、評価のゴールド v2 の a013（3 行、人間の専有領域）にかかわるものが 7 例。デモクエリの期待件数は変わらない
- 裁定の 4 は「記録の時刻は、UTC の Z つきで書かれる」としていたが、サンプルデータのイベントの時刻は、もう `+09:00`（`Demo::SampleCompositions::RECORDED_ZONE`）。`Z` なのは、帳票の保存と、すべての context の start_time

### 人間が決める点
1. 既定の値: `ANLAGE_TIME_ZONE` の既定を `Asia/Tokyo`（推す）にするか `UTC` にするか
2. 評価のゴールド a013 の 3 行: openehr-rails #92（AQL の SELECT が書いた文字を返す）を待って `2025-10-01` などに替える（推す）か、いま `+09:00` の形に替える
3. すでに保存された `…Z` の記録: 移行しない（推す）
4. openehr-rails への Issue の案（scaffold の記録の時刻を `getutc` で書く件）を起票するか
