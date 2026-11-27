- Eval: 自然言語から AQL の、接地あり・なしの測定の実装（`skoba/anlage#249`）。問いの読み込み、腕ごとの送る文、採点（主: 行の一致、副: 列の順を見ない一致、見落とし）、
  試行ごとの記録（続きから回せる）、集計、`rake evaluation:grounding`、`rake evaluation:search_coverage`。測る前に決めておくことを `docs/reports/s4-runs/preregistration.md` に書いた。
  まだ、どのモデルでも測っていない。利用者に見える変更: なし（評価の道具と文書だけ）
