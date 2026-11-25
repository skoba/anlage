# S3（検索の強化）進行ログ

計画: `docs/design/s3-search-plan.md`（承認済み、6.1 節）。裁定 ID: R-20261125-2。関連 Issue: `skoba/anlage#122`。

## R1 段 A の計画と、自己承認した判断（2026-11-25）

- 範囲: 計画書 3 節の段 A（同点の順序を決定的にする。#122）。変更は `app/lib/opt/pathcard_search.rb` の並べ替えだけ
- 基準点: anlage main `946838c`
- **自己承認した判断 A1: 同点のキーは「template_id → テンプレートの中でのカードの並び（帳票の順）」にする**
  - 計画書 3 節の案は「score → 当たった項目の強さ → template_id・path」。次の 2 点を実測で改めた
  - 「当たった項目の強さ」は段 A に入れない。項目の重みは段 B の中身で、同点のキーに入れると c015 で
    ラベルに当たる負例（ProblemList at0003）が、祖先の名前だけに当たる 2 枚より前（2 位）に来る（1 節の表からの推論。段 B で実測する）
  - path の辞書順ではなく、テンプレートの中での並びを使う。path の辞書順だと、同じテンプレートの中のカードが帳票の順と違う順に並ぶ
    （実測: LabResultReport の「臨床検査」は、帳票の順が at0005 → at0024 → at0001、path の順が at0005 → at0001 → at0024）。
    テンプレートの中での並びは OPT から決まり、登録順によらない
  - 捨てた案（path の辞書順）の実測: v1 の 17 問は Top-1 14/17 のまま、at_code まで見た MRR が 0.8431 → 0.8529（q07 が偶然に上がる）。
    根拠のない上がり方なので採らない

## R2 サイクル: 同点の順序（2026-11-25）

- Red（`bundle exec rspec spec/lib/opt/pathcard_search_spec.rb`。13 examples, 2 failures）:

  ```
  1) Opt::PathcardSearch 同点の順序は登録順によらない（#122） 同じ 4 テンプレートを別の順で登録しても、同じ並びを返す
     expected: [[1, "ProblemList", "at0003"], [1, "LabResultReport", "at0005"], [1, "LabResultReport", "at0024"], [1, "LabResultReport", "at0001"]]
          got: [[1, "LabResultReport", "at0005"], [1, "LabResultReport", "at0024"], [1, "LabResultReport", "at0001"], [1, "ProblemList", "at0003"]]
  2) Opt::PathcardSearch 同点の順序は登録順によらない（#122） 同点は template_id、…の順に並べる
     expected: [[1, "LabResultReport", "at0005"], [1, "LabResultReport", "at0024"], [1, "LabResultReport", "at0001"], [1, "ProblemList", "at0003"]]
          got: [[1, "ProblemList", "at0003"], [1, "LabResultReport", "at0005"], [1, "LabResultReport", "at0024"], [1, "LabResultReport", "at0001"]]
  ```

  3 つ目の例（score の高いカードが先）は、もとから通る（score の降順は変えていないことの pin）
- Green: 並べ替えのキーを `[-score, template_id, テンプレートの中での位置]` にした。13 examples, 0 failures
  - 途中で path の辞書順を試し、2 つ目の例が落ちた（at0001 が at0024 の前に来る）。R1 の判断 A1 のとおり、位置に改めた
- 追随: `spec/lib/tasks/evaluation_run_spec.rb` は、4 テンプレートの索引で c015 の負例が 1 位に出ることを固定していた
  （全 suite で 1 failure）。順序が決定的になった結果なので、期待値を実測に合わせた（Top-1 3/4 → 4/4、負例違反 1/4 → 0/4）
- 全 suite: 427 examples, 0 failures, 2 pending（追随のあと、落ちた spec と評価の spec を再実行して 0 failures）

## R3 段 A の before／after（2026-11-25）

`RESET=1 bundle exec rake evaluation:run`（demo_initial の 5 テンプレート）と、`evaluation_run_spec` の 4 テンプレートの索引。

| 索引 | 問い | before（main `946838c`） | after |
|---|---|---|---|
| 5 テンプレート | v1 の 17 問 | Top-1 14/17、Top-3 15/17、MRR 0.8529、負例違反 0 | 同じ |
| 5 テンプレート | v1 の 17 問（at_code まで） | Top-1 14/17、Top-3 15/17、MRR 0.8431 | 同じ |
| 5 テンプレート | v2 の card 4 問 | Top-1 4/4、Top-3 4/4、MRR 1.0000、recall@3 0.8750、負例違反 0/4、順位遵守 1/1 | 同じ |
| 4 テンプレート | v1 の 17 問 | Top-1 14/17、Top-3 15/17、MRR 0.8529 | 同じ |
| 4 テンプレート | v2 の card 4 問 | Top-1 3/4、負例違反 1/4（c015） | Top-1 4/4、負例違反 0/4 |

- 5 テンプレートの報告は、before と after で card の節が 1 字も違わない（`rake demo:reset` はテンプレートを名前の順に登録するので、
  もとの並びが template_id の順と同じだった）
- 入れる条件（v1 の Top-1 を下げない、v2 で負例が上位に出る問いを増やさない）を満たす。段 A を入れる
- #122 の acceptance criteria: 登録順が違っても同じ順序を返す spec が green。c015 が 4 テンプレートと 5 テンプレートで同じ結果
- 残ること: c015 の 4 枚は同点のまま。負例が 4 位にいるのは template_id の順（LabResultReport ＜ ProblemList）によるもので、
  検索が「検査」を「臨床」より重く見ているわけではない。段 B で扱う
