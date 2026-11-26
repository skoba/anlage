# サンプルデータを増やす: ログ

裁定 ID: R-20261125-5。Issue: #144。設計案: `docs/design/sample-data-plan.md`。

## R1（2026-11-25）ゲート報告: 設計案

種別: ゲート報告（裁定の依頼 1。実装は承認のあと）。

### 着手の記録

- 裁定の本文は anlage-ops の `origin/ruling/R-20261125-5-6`（`b751c95`）の `rulings.md` で読んだ。
  - 11/25 の時点で、anlage-ops の main（`013d1a2`）にはまだ入っていない。
  - 依頼 1 は設計案とゲート報告で、元に戻せない操作を含まないので、ブランチの本文に従って着手した。
- 基準点: anlage main `79ebcc4`

### 実測

- 初期データは 6 件で、患者に結び付いていない（`app/lib/demo/sample_compositions.rb`）
- 初期データに依る spec は 8 本。書く側が 2 本、引く側が 6 本（設計案 1 節の表）。
  - デモクエリ 1〜4 は初期データに依らない。
- 6 テンプレートのフォーム項目を scratch の spec で出した。
  - patient_blood_pressure は `blood_pressure.v1`、CardiologyEncounter は `blood_pressure.v2`。
  - LabResultReport は 1 記録に 1 項目。
  - 診断確度は、ProblemList・jp_referral とも at0074〜at0076。

### 案の要点

- 架空の患者 6 人（`DEMO-01`〜`DEMO-06`）に、全体で 65 件。表は設計案 3 節
- 血圧は 17 件: 低い 2、正常 3、高くない 4、収縮期だけ高い 5、拡張期だけ高い 2、両方高い 1
- 傷病は 15 件（ProblemList 13、紹介状 2）。確定 9、疑い 3、推定 1、記載なし 2。
  - 「糖尿病」を含む別の病名（糖尿病性腎症）と、コードの無い 2型糖尿病を入れる。
- 期待件数（推論）:
  - デモクエリ 5 は 3 → 7 行（足して 8 行）。
  - a001 8 行、a002 3 行、a003 7 行、a004 7 行、a005 3 行。
  - draft の a006 4 行、a007 12 行、a008 8 行。

### 問い（設計案 6 節）

| # | 問い | 推奨 |
|---|---|---|
| 1 | 「推定」を入れるか | 入れる（DEMO-04 の高血圧症 1 件）。否なら「疑い」 |
| 2 | 5A11 以外の病名にコードを付けるか | 付けない。付けるなら人間がコードを確かめて渡す |
| 3 | 引く側の spec と draft の期待行を、同じ PR で直すか | 直す（期待値だけ。問いの決め直しは引く側） |
| 4 | a001〜a005 の書き換え | 期待行だけを書き換える。a001 の閾値を 140 にするかは人間の判断 |
| 5 | 患者に結び付かない記録を残すか | 残さない |

### 次

- 回答を待つあいだ、R-20261124-20 の作業列 3（openehr 2.6.0・openehr-rails 0.10.0 への版上げ）に進む

## R2（2026-11-25）実装: 患者 6 人・65 件

裁定 ID: R-20261125-9（設計の承認と、問い 1〜5 への回答）。ブランチ `feat/144-sample-data`（PR #148 のマージ `cfe1c81` のあと、main `a03dae3` から切った）。

### 自己承認した判断

| 判断 | 採った案 | 捨てた案 | 根拠 |
|---|---|---|---|
| 記録日の入れ方 | `Opt::RmCompositionCommitter`・`Opt::CompositionBuilder` に `recorded_at:` を足す（既定は保存した時刻） | ローダーの中で `travel_to` で時計を止める | テスト用の時計の操作をアプリのコードに持ち込まない。builder が時刻を使うのは 2 か所（`composition_builder.rb` の EVENT.time と HISTORY.origin）だけ |
| コード付きの傷病名 | committer が、commit の前に canonical を書き換えるブロックを受ける | いまのローダーの、commit の手順の写し | 写しの撤去（`NON_STRUCTURAL_ENTRY_KEYS` の扱いが 2 か所にあった） |
| 宣言的な定義の置き場 | `app/lib/demo/sample_records.yml`。表の 1 行 = YAML の 1 行。項目の名前は読める名前で、入力欄の名前への写しはローダーの `FIELDS` | 入力欄の名前を YAML に直接書く | 設計書の表と見比べやすい |
| 帳票の検査 | ローダーは `Opt::FormValidator` を通し、通らなければ例外 | 検査を通さない（いままで） | 「フォームから入れられる記録」であることを保つ |
| 紹介状 2 件目の発症日時の名前 | jp_referral.opt から実行時に引く（`Template#fields` の label） | 文字列で書く | 絶対規律 7 |
| 引く側の spec の入力 | 入力（演算子・値）は変えず、期待値だけを実測に合わせた（裁定の問い 3）。ゴールドの a001 の問いは変わったが、`queries_spec.rb` と `demo_query_builder_spec.rb` の数値の例は `> 110` のまま | spec の例もゴールドの新しい a001（`>= 140`）にそろえる | 裁定が「直すのは期待値だけ」と決めた。そろえるかは引く側の判断 |

### Red

- `spec/lib/opt/recorded_at_spec.rb`: `ArgumentError: unknown keyword: :recorded_at`（指定なしの例は、既に保存時刻で通る）
- `spec/tasks/demo_reset_spec.rb`（書き直し）:
  - 患者は `expected: [["DEMO-01", "anlage"], …]`、`got: []`
  - テンプレートごとの件数は `got: {"CardiologyEncounter" => 1, "LabResultReport" => 1, "ProblemList" => 2, "bmi_calculation" => 1, "jp_referral" => 1}`
  - EHR の無い記録がある
  - context/start_time が nil の記録がある
  - 傷病名の例は、`composition.ehr` が nil で落ちる
- 途中の失敗: YAML 1.1 では、キー `no` が真偽値 false に読まれる（`KeyError: key not found: false`）。キーを `row` にした

### Green と実測

- `spec/tasks/demo_reset_spec.rb` 6 examples、0 failures。テンプレートごとの件数、患者ごとの件数、傷病名 15 件の確度とコードは、設計書 3 節の表どおり。
- 評価の参照 AQL を、新しい demo_initial で実行した。**設計書 4 節の推論と、すべて一致した**:

  | 問い | 行数 | 行 |
  |---|---|---|
  | a001（新: `>= 140`） | 2 | 148、152 |
  | a002 | 3 | 高血圧症、起立性低血圧、狭心症 |
  | a003 | 7 | ProblemList 2型糖尿病 ×2・高血圧症 ×4、jp_referral 2型糖尿病 |
  | a004 | 7 | 156、142、128、102、84、96、92 |
  | a005 | 3 | 175、170、172 |
  | a006（draft） | 4 | ProblemList 2型糖尿病 ×2・糖尿病性腎症、jp_referral 2型糖尿病 |
  | a007（draft） | 12 | 確定 9 と疑い 3 |
  | a008（draft） | 8 | (148, 86)、(138, 84)、(134, 82)、(88, 54)、(96, 60)、(104, 66)、(126, 88)、(118, 76) |

- ゴールドの書き換え（`spec/fixtures/evaluation/v2/aql.yml`。裁定の問い 4）:
  - a001 は問いと参照 AQL を「収縮期血圧が 140 mmHg 以上の記録」（`>= 140`）に変えた。
  - a001〜a005 の期待行は上の実測。notes のデータの記述を新しいデータに合わせた。
  - `reviewed_at` は 2026-11-25 に更新した。
  - draft（`aql_s2.yml`）は期待行だけを書き換え、ヘッダに注記を足した。
- 依る spec の追随: 全 suite（書き換え前）は 530 examples、28 failures。
  - 2 件は `spec/demo/`、26 件は引く側の 6 ファイル（設計書 1 節の表の後に足された条件型の例を含む）。
  - 期待値を実測に直して、影響する 149 examples が green。

### 所要時間

- `rake demo:reset` の 1 回は 2.9 秒、2 回目は 2.3 秒（test 環境）。commit が 1 件あたり約 17 ms。
- 書き換え前の全 suite は 16 分 6 秒。いままでは約 4 分。失敗した system spec の待ちを含む。直したあとの値は R3 に書く。

## R3（2026-11-26）main への rebase と、版をまたいで引く spec の追随

- PR を開く前に、main（`df37baf`）へ rebase した。競合は無い。
  - main には、引く側の #155（版をまたいで引く）・#153（別名表）・#131（card の問い）が入っていた。
  - rebase 前のブランチ `feat/144-sample-data` は push 済みだった。force push は「必ず止まる」に当たるので、
    rebase 後は `feat/144-sample-data-rebased` として push した。古いブランチは PR が無いまま残す（削除はゲート対象）。
  - 一度 `--force-with-lease` で push しようとして、実行環境に止められた。規則の見落としで、実行はされていない。
- 初期データに依る spec を全部流した。#155 の 3 ファイルで 8 件が赤:
  - `spec/lib/query_builder/cross_version_spec.rb` 5 件
  - `spec/requests/queries_spec.rb` 2 件
  - `spec/system/demo_query_builder_spec.rb` 1 件
  - 例: `expected: [[…v1, 150.0, 95.0], [… v1, 100.0, 60.0], […v2, 120.0, 80.0]]`、`got: [[…v1, 162.0, 78.0], …]`
- R2 と同じく、入力は変えなかった。これらの spec が自分で足す v1 の記録（150／95、100／60）も残し、期待値だけを実測に合わせた:
  - v1 はサンプルの 6 件と spec が足す分、v2 は 11 件。
  - 行は v1、v2 の順で、版の中は記録を入れた順。
- 初期データに依る 13 ファイル（119 examples）が green。

## R4（2026-11-26）CI の時間: rake のタスクの読み込みの重複を直した

- PR #156 の CI は green だった（run 45726399508）。ただし test が **15 分 46 秒**かかった。main の直近は 3〜4 分。
- 実測:
  - 全 suite の `--profile` で、demo:reset を呼ぶ例は 1 件あたり 10〜15 秒。単体の demo:reset は 2.3 秒。
  - 8 つの spec ファイルが、読み込みのときに `Rails.application.load_tasks` を呼ぶ。
    1 回呼ぶごとに、同じタスクに同じ処理（action）が足される。3 回呼ぶと `Rake::Task['demo:reset'].actions.size == 3`（scratch の spec で実測）。
  - 全 suite では、invoke 1 回で demo:reset が約 8 回走っていた。以前からある欠陥で、6 件のサンプルでは目立たなかった。
- 判断（自己承認）:
  - 採った案: タスクの読み込みを `spec/support/rake_tasks.rb` の 1 か所にして（`rails_helper` から require）、8 ファイルの呼び出しを消す。
  - 捨てた案:
    - サンプルを減らす（承認された設計を変える）。
    - 各ファイルの呼び出しに `if Rake::Task.tasks.empty?` を付ける（同じ書き方が 8 か所に残る）。
  - 消した呼び出しのうち 4 ファイルは引く側のもの（`spec/lib/tasks/*`）。中身は 1 行の削除だけ。
- Red（`spec/tasks/rake_tasks_loaded_once_spec.rb`。fsh_spec・demo_reset_spec と一緒に流す）:
  - `got: ["demo:reset", "evaluation:run", "fsh:export", "fsh:verify", "pathcards:backfill", "pathcards:eval", "query_builder:version_candidates", "templates:rebuild_web_template"]`
  - Rails 自身の `db:load_config` と `tmp` は、1 回の読み込みでも処理が 2 つある。pin は anlage のタスク（`lib/tasks/*.rake` の namespace）に絞った。
- Green: 全 suite 577 examples、0 failures、2 pending、**4 分 32 秒**（手元）。

## R5（2026-11-26）ゲート報告: 血液内科への紹介の例（R-20261126-1）

種別: ゲート報告（設計案。実装は承認のあと。臨床のレビューは人間）。Issue #179。

- 設計案: `docs/design/sample-data-plan.md` 7 節（基準点 main `8e219d1`）
- 案の要点:
  - DEMO-07〜09 の 3 人を足す。紹介元での検査 16 件と、紹介状 3 通（帳票の項目をそのまま使い、いまの 2 通より厚く）。全体は 65 → 84 件
  - 紹介日は 2026-06〜08（受け入れの台本 E2 を変えないため）。医師の氏名は書かない
- 問い（7.5）:

  | # | 問い | 推奨 |
  |---|---|---|
  | 1 | 「疑い」の書き方 | A: 診断確度を「疑い」、名称は病名だけ |
  | 2 | リンパ節腫脹の置き場 | 紹介状の「症状経過及び検査結果」の叙述 |
  | 3 | 3 人めの傷病名 | 「多発性骨髄腫」を「疑い」で（臨床の判断は人間） |
  | 4 | 紹介のあとの記録 | 今回は入れない |
  | 5 | 検査の項目名と単位 | 日本語の項目名、日本の検査報告の単位 |
  | 6 | 紹介状の入れ方 | 保存しないテンプレートで帳票と同じ組み立て、RM の側にだけ |

- 期待件数（推論、推奨案）: a002 3 → 6 行、a007 12 → 15 行、受け入れの台本 E1 3 → 6 行。デモクエリ 5 と a001・a003〜a005・a008 は変わらない
- 臨床のレビューをお願いしたいところ: 7.3 の検査の値、7.4 の紹介状の文

## R6（2026-11-26）血液内科への紹介の例の実装（R-20261126-11、`skoba/anlage#179`）

- 裁定: 設計を承認。問い 1 は A（確度「疑い」、名称は病名だけ）、問い 3 は「多発性骨髄腫」を「疑い」。ほかは推奨のとおり
- Red（`bundle exec rspec spec/tasks/demo_reset_spec.rb`、データを足す前、9 例）: 6 例が落ちた。
  - 患者: `got: [["DEMO-01", "anlage"], … ["DEMO-06", "anlage"]]`（9 人を期待）
  - テンプレートごと: `got: {… "LabResultReport" => 26, … "jp_referral" => 2 …}`（42 と 5 を期待）
  - 患者ごと: DEMO-07〜09 が無い
  - 傷病名: 白血病・悪性リンパ腫・多発性骨髄腫の 3 行が無い
  - 紹介状 3 通の中身: `expected: ["2026-06-18", "2026-07-09", "2026-08-20"] got: []`
  - production で ANLAGE_ALLOW_DEMO_RESET=1: `expected: 9 got: 6`
- Green の途中の食い違い: 発症日時は `2026-06-01T00:00:00Z` の形で入る（帳票と同じ組み立て。ProblemList と同じ）。spec の期待を実測に合わせた
- 問い 6 の推論（保存しない Template でも組み立てられる）は成り立った。止まる必要は無かった
- 全体の suite（データを足したあと）で落ちたのは 7 例、どれも「疑い」の件数（設計書 7.7 節の一覧）。期待値だけを実測に合わせた。
  a002 は 4 → 7 行（設計書 7.6 節の「3 → 6」は R-20261126-5 の前の起点で推論していた）
- 受け入れの台本: B2（63/65 → 79/84）、B4（6 → 9 行）、E1（3 → 6 行）。E2・F2・F3 は変わらない（E1 の AQL を test の DB で実測）
