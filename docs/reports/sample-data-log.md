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
