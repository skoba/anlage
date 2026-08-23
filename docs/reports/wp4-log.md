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
