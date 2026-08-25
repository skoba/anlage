# WP4（検索評価ハーネス）進行ログ

explore→planフェーズの実測記録。R1〜。

---

## R1: Step 0（前提）・Step 1（explore）

### Step 0: 元プロンプトWP4節の原文再読

`claude-code-prompt_semantic-pathcards.md`「### WP4: 評価ハーネス」全文（転記）:

> - 「日本語臨床記述→正解アーキタイプ（可能ならパスまで）」形式の評価器。指標はtop-1 / top-3精度
> - シード20問を提案する。正解はCKM実在アーキタイプに限る（人間レビューで確定し、コミュニティで100問へ拡充する前提の設計にする）
> - CIで実行可能にする
> - **DoD**: `rake pathcards:eval`一発でスコアが表示される

**解釈のずれ（#38/WP3の型どおり承認事項に上げる）**: 本タスクの指示文（Step 1-1「ゴールドスタンダード(クエリ→正解カード集合)」、Step 1-2「Recall@k / MRR等」）は、1クエリに対し**複数の正解が存在しうる集合ベースの評価**（情報検索の標準的なRecall/MRR）を示唆する。一方、原文プロンプトは「正解アーキタイプ」（**単数**）「top-1 / top-3精度」（**単一正解に対する的中率**）と明記しており、集合ベースではなく**1問=1正解アーキタイプ**の単一ラベル評価を意図しているように読める。両者は近い場面では同じ挙動になるが（1問1正解の場合、top-k精度とRecall@kは同義）、将来1問に複数の妥当な正解archetypeがありうる設問（例:「血圧」→収縮期・拡張期どちらも正解）を許容するかどうかで設計が分岐する。→ 承認事項として計画書に明記する。

### Step 1: explore実測結果

**1. CIの実行実態（再確認）**: `.github/workflows/ci.yml`全40行を確認。`scan_ruby`（brakeman・bundler-audit）と`scan_js`（importmap audit）の2ジョブのみで、**`bundle exec rspec`や`rake`タスクの実行は一切無い**（WP3探索時の発見の再確認）。「CIで実行可能にする」を字義通り満たすには、`pathcards:eval`用の新規CIジョブ追加が必要になるが、これは現行CIの構造（rspec自体を回していない）を変える話であり、WP4のスコープを超える可能性がある。→ 承認事項として提示する。

**2. 評価データの母数**: 現有4テンプレート（golden fixture 3件＋bmi_calculation実測）を実測で棚卸しした結果、**カードは15枚だが、ユニークなarchetype_idは7種類**（`blood_pressure.v2`・`laboratory_test_result.v1`・`laboratory_test_analyte.v1`・`problem_diagnosis.v1`・`height.v2`・`body_weight.v2`・`body_mass_index.v2`）。シード20問を「正解はCKM実在アーキタイプに限る」制約で作る場合、7種類のarchetypeに対して平均約2.9問を割り当てる計算になり、**多くの設問が同一archetypeを異なる言い回し・観点（同義語・複合語・表記ゆれ）で問う形にならざるを得ない**（実物主義上、これ以上のarchetype多様化にはOPT追加供給が必要）。

**3. WP3の18クエリの再利用可否**: `docs/reports/wp3-log.md` R1を実測確認した結果、18クエリは**カテゴリ別集計（8/18・3/18・3/18・1/18・実測外1/18・1/18の内訳）としてのみ記録**されており、個々のクエリ文字列と正解archetype・実際のヒット可否を全問分保持した構造化データは存在しない。名指しで確認できるのは各カテゴリの代表例のみ（「収縮期」「収縮期血圧」「拡張期血圧」「身長体重」「BMI」「体格指数」「既往」「疑い」等、実測で約7-8問相当）。→ **WP3から丸ごと流用できるのはこの7-8問相当のみ**。残りはWP4で新規に設問化する必要がある。

**4. 検索サービスの出力形**: `Opt::PathcardSearch.call(query)`（`app/lib/opt/pathcard_search.rb`）はスコア降順の配列を返し、各要素は`identity.archetype_id`・`identity.at_code`を含むカードhashそのもの。top-k精度・MRRいずれの算出にも直接使える（`results.first(k).map { |r| r.dig("identity","archetype_id") }`で十分）。

**5. 既存rakeタスクパターン**: `lib/tasks/pathcards.rake`（WP3 C2、`pathcards:backfill`）が唯一の先例。`namespace :pathcards do ... task xxx: :environment do ... end end`という最小形。`pathcards:eval`もこの直下に追加するのが自然。

### Step 2への引き継ぎ

上記5点（原文との解釈のずれ・CI実行実態・母数7archetype・WP3クエリの部分再利用性・出力形・rakeタスク先例）を踏まえ、評価データ形式・指標・実行方式・Phase 2比較設計・承認事項を`docs/design/wp4-plan.md`に起こす。

---

## R2: 人間レビュー完了・17問体制への再実行（2026-08-25）

### 評価データの反映

`spec/fixtures/pathcards_eval_seed.yml`の人間レビュー（`skoba/anlage#14`裁定3）が完了。
反映内容: 修正4問（q06「検査」→「検査名」修正意図の記載＝下記の食い違い参照／q07
「分析」→「検査結果」／q09「判定」→「BMI判定」／q15「臨床検査」→「検体検査」）・
廃止3問（q13「身長体重」・q17「体格指数」・q19「検体」、いずれも正解不在または
検証係として不適格と判定され削除）。分母は20→17。

**発見（YAML構文エラー、Claude Codeが修正）**: q09の`notes`末尾に`""`（二重引用符の
誤り）があり`YAML.load_file`が構文エラーで全体失敗する状態だった。ゴールド本体の
「内容」ではなく構文エラーの機械的修正のため、末尾の余分な`"`1字を除去して修正
（内容は変更していない）。

**発見（未解消の食い違い、要人間判断）**: q06の`notes`は「query を「検査」→「検査名」に
修正」と記載しているが、実際の`query`フィールドは「検査」のまま（修正が未適用）。
Claude Codeはゴールド本体（`query`）を推測で書き換えず、この食い違いをそのまま
本ログに記録するに留めた。実測では現行の`query: "検査"`のままintent_tag「bigram成立
想定」どおりrank=0（top-1的中）で成立している。noteどおり`query`を「検査名」へ
実際に修正するか、noteの記述を「検討したが不採用」に訂正するかは人間の判断を要する。

### intent_tag再検証（文言変更4問）

実際に索引済み4テンプレート（`CardiologyEncounter`・`LabResultReport`・`ProblemList`・
`bmi_calculation`）に対し`Opt::PathcardSearch.call`を実行し、17問全問のrankを実測:

- q06「検査」: rank=0（top-1的中）。intent_tagどおり成立
- q07「検査結果」: rank=1（top-3的中・top-1不成立）。q06が索引する`検査名`カードと
  bigram「検査」を共有し1位を占めるため2位着地——`notes`記載の予測（「検査名カードとの
  bigram競合により順位変動の可能性あり」）が的中。機序は直接bigram一致であり複合語の
  部分語分解とは異なるため、intent_tag「bigram成立想定」は維持（「成立が見込まれる」の
  定義はヒット可否を指しランクは問わない、ファイル冒頭凡例）
- q09「BMI判定」: rank=0（top-1的中）。intent_tagどおり成立
- q15「検体検査」: rank=0（top-1的中）。旧クエリ「臨床検査」にあったProblemListとの
  偽陽性競合（2位問題）が解消されたことを確認（top-3内にProblemListは出現しない）

### 17問体制での実測結果

`bundle exec rake pathcards:eval`実行（`docs/reports/wp4-eval-log.md`
`2026-08-24T23:57:03Z`エントリに記録済み）:

- Top-1精度: 14/17 (82.35%)
- Top-3精度: 15/17 (88.24%)
- 完全失敗率: 2/17 (11.76%)
- MRR: 0.8529
- intent_tag別内訳: bigram成立想定 11/11・複合語 4/4・同義語ギャップ 0/2
- 完全失敗: q16「BMI」・q18「既往」（いずれも意図的収録、`notes`参照）

`spec/lib/tasks/pathcards_eval_spec.rb`の期待値を上記実測へ更新（20問時代の
`q17`/`q19`失敗一覧記載も削除）。`bundle exec rspec`全件（97 examples, 0 failures）・
`bin/rubocop -f github`（exit 0）で確認済み。

### 同梱4件（docs反映）

1. `docs/design/wp3-plan.md`: 「BMI対体格指数」の例示を「BMI対英語ラベル
   (Body mass index)」に訂正（4箇所）。当初例示の「体格指数」はq17廃止判断
   （記録語彙レジスターに不在）により偽同義の例だったと判明したため。
   embedding必須の結論（Phase 2の存在理由）自体は変更なし
2. `docs/demo/opt-catalog.md`: `bmi_calculation.opt`の言語欄に脚注を追加
   （宣言はenだが`at0013`のみjaラベル「判定」混在、実測`bmi_calculation.opt:1678`）
3. `docs/design/wp4-plan.md`: 将来課題節を新設し、Phase 2起動時の評価v2設計
   （期待集合オプション・負例セット・保留問2件の出題化）を1項目として記録
4. 同節に語彙レジスター観察を追記（記録語彙/説明語彙・節名/モデリング語彙の
   2軸、一字差ペア2組「既往/既往歴」「検体/検体検査」、分布定量2件——WP5/
   voice_aliases設計への入力として横断集約）

### 規約反映

`CLAUDE.md`に「評価データの人間レビュー中の編集範囲」節を新設。ゴールド本体
（`query`/`expected_archetype_id`/`expected_at_code`/`notes`）は人間レビュー進行中は
人間の専有領域とし、エージェントは読み込み系・spec側のみ変更可と明文化。

---

## R3: q06記入漏れの完遂・WP4完全クローズ（2026-08-26、人間の明示委任）

R2で発見した「q06のnotesとqueryの食い違い」（notesは「検査→検査名に修正」と
記載していたが`query`フィールド未反映）について、人間から本フィールド反映の
明示委任を受けた。`query: "検査"`→`query: "検査名"`に修正し、notesへ
「フィールド反映 2026-08-26・委任による」を追記。

**再実行結果**: 数値は不変（Top-1 14/17・Top-3 15/17・完全失敗率 2/17・
MRR 0.8529・intent_tag内訳: bigram成立想定11/11・複合語4/4・同義語ギャップ0/2）。
q06個別rankも変更前後で0（top-1的中）のまま——予測どおりq06の経路のみが
変わり、他問への影響は無いことを確認した（q07のrank=1・top3構成も不変）。
`docs/reports/wp4-eval-log.md`の`2026-08-25T00:16:55Z`エントリ（0/17・全問
失敗）はテストDBが未索引の状態で誤って実行した結果であり、実装の測定値
ではないため削除した（索引済み状態での再実行が`2026-08-25T00:17:09Z`
エントリ）。

**タグ別成績の定義（明記）**: `intent_tag`別内訳の「hit」は経路成立
（正解archetypeがtop-3以内に出現、`hit`列＝`rank`が非nil）を指し、
top-1精度とは別軸である。例: q07はbigram成立想定に分類され「hit」に
数えられるが、実際のrankは1（top-3内・top-1では不成立）。tag別内訳の
数字を「top-1的中率」と読み違えないこと。

**WP4完全クローズ**: `skoba/anlage#14`のAcceptance criteria（17問体制での
`rake pathcards:eval`実行・人間レビュー完了・spec期待値の実測追従・CI
green確認）すべて充足。完了記録は`docs/design/wp4-plan.md`末尾に記載。
