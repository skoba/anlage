# 回したときの条件（qwen3:4b。2026-11-28）

裁定 ID: R-20261128-3。決めたことは `docs/reports/s4-runs/preregistration.md`。集計は、同じフォルダの `report.md` と、`../2026-11-28-qwen3-4b-seed1/report.md`。

- commit: `a89771c`（openehr 2.9.0、openehr-rails 0.14.1、日時の項目での並べ替えが入った main。main の CI run 46112151883 green）。
  この commit に固定した worktree で回した。測る前に、正解の行の spec（`spec/lib/evaluation/nl_queries_spec.rb` と `spec/lib/evaluation/grounding`）の 49 例が green
- モデル: `qwen3:4b`（ID `359d7dd4bcda`）、Ollama 0.40.18、像の digest `1cabd20e…c913ec`。preregistration と同じ。コンテナの上限は、メモリ 5 GB・CPU 4
- 腕は g_selection だけ（preregistration のとおり）。外には、何も送っていない

| 回 | 始めた時刻（JST） | 測る前の空きメモリ（available／全体） | 測る前の load average | 試行 | かかった時間の合計 | 1 試行の中央値（最小〜最大） |
|---|---|---|---|---|---|---|
| 5 回（温度と乱数の種は指定しない） | 14:33 | 8.1Gi／15Gi | 1.44／1.45／1.77 | 185 | 72.6 分 | 20.0 秒（7.0〜78.0 秒） |
| 乱数の種を固定した 1 回（`SEED=1`、`TEMPERATURE=0`） | 15:51 | 4.5Gi／15Gi（モデルを読み込んだままのコンテナの分を含む） | 6.11／5.21／5.03 | 37 | 20.5 分 | 35.2 秒（16.5〜45.9 秒） |

- 時間は、参考。ほかのレーンも動いていた。2 つめの回は、負荷が高いときに回した（1 試行の中央値が長い）。正答率は、負荷に左右されない
- 2 つめの回の前の空きメモリ（4.5Gi）は、コンテナの上限（5 GB）を下回っている。5 回の測定に続けて、止めずに回した
  （コンテナは、すでにモデルを読み込んでいて、その分が「使用中」に入っている）。呼び出しの失敗は、どちらの回も 0
