# 測定の集計

- アダプタ: local（qwen3:4b）。応答に入っていたモデルの名前: qwen3:4b
- 腕: g_selection。くり返し: 5 回。試行: 185。索引のカード: 18 枚
- 問いのファイルの sha256: bf673fadcdbb5d9637f0dc8c8e25b5651f3f88450b3689a2835005f941cae9d9。commit: a89771cf59d21dde88ef12ba3183807163fb4265。始めた時刻: 2026-11-28T05:33:10Z
- 出力の形（JSON スキーマ）を渡した腕: g_selection

## すべての試行

| 腕 | 試行 | 正解 | 見落とし | 不正解 | リンタで落ちた | 実行できない | 読めない | 呼び出しの失敗 | 列の順を見ない一致 |
|---|---|---|---|---|---|---|---|---|---|
| g_selection | 185 | 45 | 21 | 72 | 8 | 0 | 39 | 0 | 45 |

## 主の数字（値の言い換えの文を除く）

| 腕 | 試行 | 正解 | 見落とし | 不正解 | リンタで落ちた | 実行できない | 読めない | 呼び出しの失敗 | 列の順を見ない一致 |
|---|---|---|---|---|---|---|---|---|---|
| g_selection | 175 | 45 | 21 | 67 | 8 | 0 | 34 | 0 | 45 |

## 問いごとのゆれ（主の数字の範囲で）

| 腕 | 問い | いつも正解 | いつも不正解 | ゆれた | 回ごとの正答率の最小〜最大 |
|---|---|---|---|---|---|
| g_selection | 35 | 6 | 22 | 7 | 20〜29 % |

## 問いごと

| 問い | 腕 | 正解 | 見落とし | 列の順を見ない一致 | 種類と印 |
|---|---|---|---|---|---|
| n001-1 | g_selection | 0/5 | 5/5 | 0/5 | base |
| n001-2 | g_selection | 0/5 | 5/5 | 0/5 | chart、abbrev |
| n001-3 | g_selection | 0/5 | 5/5 | 0/5 | explain |
| n001-4 | g_selection | 2/5 | 0/5 | 2/5 | base、named_template |
| n001-5 | g_selection | 0/5 | 0/5 | 0/5 | base、named_template |
| n002-1 | g_selection | 0/5 | 0/5 | 0/5 | base |
| n002-2 | g_selection | 4/5 | 0/5 | 4/5 | chart |
| n002-3 | g_selection | 1/5 | 0/5 | 1/5 | modeling |
| n003-1 | g_selection | 5/5 | 0/5 | 5/5 | base |
| n003-2 | g_selection | 2/5 | 0/5 | 2/5 | chart |
| n004-1 | g_selection | 0/5 | 0/5 | 0/5 | base |
| n004-2 | g_selection | 0/5 | 0/5 | 0/5 | chart |
| n004-3 | g_selection | 0/5 | 0/5 | 0/5 | chart、abbrev、value_paraphrase |
| n005-1 | g_selection | 5/5 | 0/5 | 5/5 | base |
| n005-2 | g_selection | 4/5 | 0/5 | 4/5 | explain |
| n006-1 | g_selection | 5/5 | 0/5 | 5/5 | base |
| n006-2 | g_selection | 0/5 | 0/5 | 0/5 | chart |
| n006-3 | g_selection | 5/5 | 0/5 | 5/5 | modeling |
| n009-1 | g_selection | 0/5 | 0/5 | 0/5 | base、見落としを見分けられない |
| n009-2 | g_selection | 0/5 | 0/5 | 0/5 | chart、abbrev、見落としを見分けられない |
| n009-3 | g_selection | 0/5 | 0/5 | 0/5 | explain、見落としを見分けられない |
| n010-1 | g_selection | 0/5 | 0/5 | 0/5 | base |
| n010-2 | g_selection | 0/5 | 0/5 | 0/5 | chart |
| n010-3 | g_selection | 0/5 | 0/5 | 0/5 | explain |
| n011-1 | g_selection | 0/5 | 1/5 | 0/5 | base |
| n011-2 | g_selection | 0/5 | 5/5 | 0/5 | chart |
| n012-1 | g_selection | 1/5 | 0/5 | 1/5 | base |
| n012-2 | g_selection | 0/5 | 0/5 | 0/5 | chart |
| n013-1 | g_selection | 5/5 | 0/5 | 5/5 | base |
| n013-2 | g_selection | 0/5 | 0/5 | 0/5 | explain |
| n013-3 | g_selection | 0/5 | 0/5 | 0/5 | explain |
| n014-1 | g_selection | 5/5 | 0/5 | 5/5 | base |
| n014-2 | g_selection | 1/5 | 0/5 | 1/5 | explain |
| n101-1 | g_selection | 0/5 | 0/5 | 0/5 | base |
| n101-2 | g_selection | 0/5 | 0/5 | 0/5 | chart、abbrev、value_paraphrase |
| n102-1 | g_selection | 0/5 | 0/5 | 0/5 | base |
| n102-2 | g_selection | 0/5 | 0/5 | 0/5 | chart |

## 限界

- 問いは 37 文。数ポイントの差は言えない。大きな差だけを結果として読む
- 問いは、このアプリのカードから作った。別のテンプレートや、別の診療科の語で、同じ成績になるとは言えない
- 「接地あり」の腕は、索引のカードをすべて渡している（18 枚）。検索で絞った候補ではない。索引が大きいときに同じ成績になるとは言えない
- 見落とし（血圧の片方の版だけを引いた答え）は、正解にも不正解にも数えていない。片方の版に当たる記録が無い問い（a009 の文）は、見落としを見分けられない
- モデルの出どころは、この記録では 1 つ（local）。同じ ID のモデルでも、日が変われば中身が変わりうる
