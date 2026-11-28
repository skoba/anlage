# 記録の時刻を、配備先の時刻帯つきで書く（計画）

- 状態: **ゲート待ち**（`skoba/anlage#291`。R-20261128-16 の 4）。実装はゲートのあと
- 進行記録: `docs/reports/time-zone-log.md`
- 実測の基準: anlage の `deps/289-openehr-rails-0150`（`87d5f55`。openehr-rails 0.15.0、openehr 2.9.0）。
  openehr 2.10.0 は未公開なので、2.10.0 の比べ方は台帳と先方の説明からの推論（3.3 節）

## 1. いま（実測）

| 書く道 | イベントの時刻・`HISTORY.origin` | context の `start_time` |
|---|---|---|
| 帳票の保存（`Opt::RmCompositionCommitter`、`recorded_at` なし） | `2026-11-28T09:20:40Z` | `2026-11-28T09:20:40Z` |
| サンプルデータ（`Demo::SampleCompositions`、`RECORDED_ZONE` = Asia/Tokyo の 9 時） | `2026-02-10T09:00:00+09:00` | `2026-02-10T00:00:00Z` |
| scaffold の記録（openehr-rails の `EventTimes.stamp!`） | `composed_at` を `getutc` で書く（`…Z`） | `composed_at`（`Time`） |

- `config/application.rb:42` の `config.time_zone` はコメントのまま。`Time.zone` は UTC（`bin/rails runner` で実測）
- `app/lib/opt/composition_builder.rb:427-428` の `dv_date_time` は `time.iso8601`。書かれるオフセットは、渡された `Time` の時刻帯で決まる
- context の `start_time`: anlage は `Time` を `CompositionCommitter.commit(context_start_time:)` に渡す。openehr-rails 0.15.0 は、`Time` を時点として保存し、`…Z` で返す。
  `String` を渡すと、書いた文字のまま残す（`openehr-rails` v0.15.0 `ef574d1` の `lib/openehr_rails/rm/composition_committer.rb` の `merge_context_start_time`）
- 患者の画面の日付（`PatientsHelper#recorded_date`）は、すでに `RECORDED_ZONE`（Asia/Tokyo）で出している。AQL 照会とクエリビルダーの結果の表は、AQL が返す文字をそのまま出す
- AQL の `SELECT` は、日時を正規化した時点で返す（openehr-rails の既知の制限、#92）。日付だけの値（発症日 `2025-10-01`）も `2025-10-01T00:00:00Z` で返る

## 2. 案（1 つに絞る）

**推す案 A: 設定 `ANLAGE_TIME_ZONE`（環境変数）、既定は `Asia/Tokyo`。`config.time_zone` に入れる**

```ruby
# config/application.rb
config.time_zone = ENV.fetch("ANLAGE_TIME_ZONE", "Asia/Tokyo")
```

あわせて、anlage の中で次をそろえる:

1. `Demo::SampleCompositions::RECORDED_ZONE` を `Time.zone` に寄せる（時刻帯を 2 か所で持たない）。`PatientsHelper#recorded_date` も `Time.zone` で出す
2. context の `start_time` を、`Time` ではなく `iso8601` の文字（オフセットつき）で gem に渡す（`Opt::RmCompositionCommitter#context_start_time`）。
   修正の版は、元の記録の書いた文字を引き継ぐ
3. 日まで・月までのイベントの時刻（既知の制限 23）は、`Time.zone` のその日の 0 時として読み、その日の列に出す（`Opt::RecordedTime`）

理由:
- 配備先が日本の診療所なら、既定のままで、記録の日付が診療の日付とそろう。サンプルデータとデモの壇上の値は、もう Asia/Tokyo で書いている
- 環境変数なら、配備ごとに変えられる（世界公開のあとの利用者は、`ANLAGE_TIME_ZONE=UTC` などにする）。設定ファイルを書き換えずに済む
- `config.time_zone` は Rails の決まった口で、`Time.current`・`Time.zone.parse` が全部これに従う。anlage の中に、別の仕組みを足さない

捨てた案:
- B: 既定を `UTC` のまま、設定だけ足す。いまの出力が変わらないのは良いが、デモと配備の既定で、記録の日付が 9 時間ずれる問題が残る（裁定の 4 の問題が、設定し忘れで起きる）
- C: `config/application.rb` に `Asia/Tokyo` を書くだけ（設定なし）。配備ごとに変えられない
- D: 時刻帯の名前を定義の組（`bundle.yml`）に持たせる。時刻帯は配備の性質で、画面の定義の性質ではない

**人間が決める点**: 既定の値（`Asia/Tokyo` か `UTC` か）。上は `Asia/Tokyo` を推す

## 3. 変わるもの（実測）

`config.time_zone = "Asia/Tokyo"` の 1 行だけを入れた一時の worktree（`87d5f55` の上。消した）で、system を除く suite を回した:
**958 examples, 15 failures**（9 ファイル）。2 案目以降（2 節の 1〜3）は、まだ入れていない。system spec は手元で回していない（CI で見る）

### 3.1 期待値が変わる spec（15 例）

| ファイル | 例 | 変わりかた |
|---|---|---|
| `spec/lib/opt/recorded_at_spec.rb` | 2 | イベントの時刻 `2026-01-15T00:00:00Z` → `2026-01-15T09:00:00+09:00`（同じ時点） |
| `spec/requests/record_versions_spec.rb` | 1 | 修正の版のイベントの時刻 `…T01:00:00Z` → `…T10:00:00+09:00` |
| `spec/requests/referral_date_query_spec.rb` | 2 | 紹介日 `2026-04-15T00:00:00Z` → `2026-04-15T09:00:00+09:00` |
| `spec/demo/aql_queries_spec.rb` | 1 | デモクエリ 4 の行 `2026-03-15T00:00:00Z` → `2026-03-15T09:00:00+09:00`（件数は 1 のまま） |
| `spec/lib/query_builder/runner_spec.rb` | 1 | 発症日時の並べ替えの行が `…T09:00:00+09:00`（順は同じ） |
| `spec/requests/queries_spec.rb` | 1 | 同上（画面の表） |
| `spec/lib/evaluation/runner_spec.rb` | 2 | 評価のゴールド v2 の aql 12 問のうち 1 問（a013）が mismatch |
| `spec/lib/evaluation/builder_route_spec.rb` | 1 | 同じ a013 |
| `spec/lib/evaluation/grounding/scorer_spec.rb` | 4 | 同じ a013 の行を使う問い（n013） |

- 3 例（`recorded_at_spec`・`record_versions_spec`）は、anlage が原本に書く時刻のオフセットが変わったもの。12 例は、AQL が正規化して返す日時（イベントの時刻、発症日、紹介日）の書き方が、`Time.zone` に従って変わったもの（行の数と順は変わらない）
- AQL の `SELECT` が返す日時の形は gem の側（openehr-rails #92。openehr の版待ち）。#92 が直れば、書いた文字（`2025-10-01`）が返り、12 例の多くは時刻帯によらなくなる見込み（推論）

### 3.2 golden とデータ

- **評価のゴールド**（`spec/fixtures/evaluation/v2/aql_s2.yml` の a013 の `expected_rows` の 3 行。`2025-10-01T00:00:00Z` など）: 人間の専有領域。変えるなら、裁定で値を決める。
  #92 を待って、書いた文字（`2025-10-01`）に替えるのが筋（推す。そのときまで、ゴールドは動かさず、時刻帯の切り替えも待つ）
- サンプルデータ（`app/lib/demo/sample_records.yml`）: 変えない。記録日の書き方はもう Asia/Tokyo の 9 時。2 節の 2 で、context の `start_time` が `…Z` から `+09:00` に変わる（`demo_initial` の実測で、gem の記録 84 件、うち anlage の原本 79 件）
- デモの問い（`docs/demo/aql-queries.md`）: 期待件数は変わらない。クエリ 4 の行の書き方が変わる。文書の例の値を合わせる
- FHIR の出力: 実行時の記録の `effectiveDateTime` は書いた文字（0.15.0）。帳票から保存した記録は `…Z` から `+09:00` に変わる（推論。FHIR の spec は Asia/Tokyo でも通ったので、`Z` を固定する例は無い）
- 画面の表示: 患者の画面の日付は変わらない（もう Asia/Tokyo）。AQL 照会とクエリビルダーの結果の表で、日時の文字が `+09:00` になる

### 3.3 openehr 2.10.0 の比べ方との関係（推論）

- 2.10.0 は、書かれた成分で比べる（R-20261128-11）。日付だけの条件（`>= '2026-03-01'`）は、記録に書かれた日付と比べる
- 帳票の記録を `+09:00` で書けば、日本の 3 月 1 日 8 時の記録は `2026-03-01T08:00:00+09:00` で、3 月 1 日に入る。いまの `Z` では `2026-02-28T23:00:00Z` で、2 月 28 日に入る
- 2.10.0 の公開のあと、実測で確かめる（引く側の R-20261128-17 と一緒に）

## 4. すでに保存された記録（`…Z` のもの）

**推す案: 移行しない**

- 時点は同じなので、並べ替えと、時点どうしの比べ方（`>=` を時点で比べる道）は変わらない
- 日付だけの条件では、`Z` の記録は UTC の日付で比べられる（日本の朝 9 時より前の記録は、前の日に入る）。これは既知の制限として書く（新しい番号）
- 書き直す移行は、原本の文字を変える（記録の改ざんに近い。openEHR では新しい版を作ることになる）。データの移行はゲート（「全開の進め方」の「必ず止まる」）なので、要るなら別の裁定で
- デモと評価のデータは、`demo:reset` で作り直すので、新しい書き方になる

## 5. openehr-rails の側に要るもの（Issue の案。起票は人間の判断のあと）

- **scaffold の記録の時刻**: `OpenehrRails::EventTimes.stamp!` が `composed_at` を `getutc` で書く（v0.15.0 `lib/openehr_rails/event_times.rb`）。
  案: `Time.zone` で書く（`composed_at.in_time_zone.iso8601`）か、書く時刻帯を設定にする。context の `start_time` も、同じ文字で残す
- **AQL の `SELECT` の日時**（#92。openehr の版待ち）: 書いた文字を返すようになれば、3.1 の 12 例のうち、書いた文字が時刻帯によらないもの（発症日と a013）は、時刻帯によらなくなる
- 文面の案は、ゲートのあと `docs/upstream-candidates.md` に書く（上流への報告は人間）

## 6. 実装の段（ゲートのあと）

1. 設定（2 節の式）と、時刻帯を 1 か所に寄せる（`RECORDED_ZONE`・`recorded_date`）。Red: 設定した時刻帯で、帳票の保存の時刻が `+09:00` で書かれる spec
2. context の `start_time` を文字で渡す。Red: 紹介日が `+09:00` で残る spec
3. 日まで・月までのイベントの時刻を、その日の列に出す（既知の制限 23 を消す）
4. 3.1 の spec の期待値を実測に合わせる（もとの値を PR に書く）。評価のゴールド a013 は、裁定で決めた値にする（推す: #92 の版まで、時刻帯の既定の切り替えを待つか、ゴールドの裁定を先にもらう）
5. 既知の制限（`Z` の記録は UTC の日付で比べられる）を足す

**人間が決める点（まとめ）**
1. 既定の値: `Asia/Tokyo`（推す）か `UTC`
2. 評価のゴールド a013 の 3 行: #92 を待って書いた文字に替える（推す）か、いま `+09:00` に替える
3. すでに保存された記録: 移行しない（推す）
4. openehr-rails への Issue（5 節）を起票するか
