# 受け入れの台本（v0.2.0）の実行の記録

裁定 ID: R-20261126-2（2 の 3）。Issue: #173。台本: `docs/demo/acceptance-v0.2.0.md`。

## R1（2026-11-26）まっさらな Docker で台本を最後まで通した

- 基準点: anlage main `56f1796`（#165・#166・#167・#169・#172・#175 のあと）。この main から `docker build -t anlage .`（A1）
- 環境: 開発機（WSL2）の Docker。volume は新しく作った（A2 の前に `anlage-storage` は無かった）
- 実行: A1〜B2 は shell のコマンド。A5〜I2 は、headless Chrome（Capybara・Selenium）で、台本と同じ操作列を `http://demo:<pw>@localhost:8080` に対して実行した
  - 実行の道具（ruby のスクリプト）は scratch に置いた。リポジトリには入れない（台本は人間が画面で通すもので、道具はこの記録のためのもの）
  - 1 回目（同じ日、同じ手順）は、道具の誤り（選択子、画面の読み直しを待たない）で 8 行が失敗した。製品の側の不具合ではないことを、
    該当の行を HTTP で直接たたいて確かめてから、道具を直して、新しい volume で 2 回目を最初から通した。下は 2 回目
- **結果: 31 行すべて、台本どおり**（台本の誤り 4 か所は直した。下の「台本を直したところ」）

| # | 結果 | 出たもの |
|---|---|---|
| A2 | PASS | 3664083da903 |
| A3 | PASS | 200 |
| A4 | PASS | 401 |
| A5 | PASS | h1=テンプレートの取り込み warning="参照実装です。認証がありません。実在の患者のデータを入れないでください。外から届く場所で動かさないでください。" |
| A6 | PASS | 患者:true テンプレート:true カルテ記録一覧:true パスカード検索:true クエリビルダー:true AQL 照会:true |
| B1 | PASS | demo:reset は production では実行しない（全データを消して入れ直す。実行するなら ANLAGE_ALLOW_DEMO_RESET=1 を与える） |
| B2 | PASS | templates=5 compositions=63 rm_compositions=65 |
| B3 | PASS | CardiologyEncounter／LabResultReport／ProblemList／bmi_calculation／COLNEC Patient Blood Pressure.v0 |
| B4 | PASS | DEMO-01,DEMO-02,DEMO-03,DEMO-04,DEMO-05,DEMO-06 |
| C1 | PASS | notice="患者を選んでいません。保存するには、先に患者を選んでください。" save_button=false |
| C2 | PASS | h1=患者: DEMO-01 records=17 |
| C3 | PASS | いまの患者: DEMO-01 |
| D1 | PASS | h2=テンプレートの取り込み: jp_referral version=登録版 v1.0.0／テンプレート版 0.2.0 |
| D2 | PASS | cards=6 登録版 v1.0.0／テンプレート版 0.2.0 |
| D3 | PASS | notice=false save=true |
| D4 | PASS | flash=保存しました h1=カルテ記録: jp_referral |
| D5 | PASS | records=18 first=jp_referral — 2026-11-26 02:03:13 UTC |
| E1 | PASS | [["X病院", "2型糖尿病", "2026-08-03T00:00:00Z"], ["Y病院", "慢性腎臓病", "2026-11-26T02:03:12Z"], ["X病院", "狭心症", "2026-05-12T00:00:00Z"]] |
| E2 | PASS | [["Y病院", "慢性腎臓病", "2026-11-26T02:03:12Z"]] saved_at~2026-11-26T02:03:12Z |
| F1 | PASS | 2 行 ["148.0", "152.0"] |
| F2 | PASS | 9 行 |
| F3 | PASS | 12 行 {"2型糖尿病" => 3, "糖尿病性腎症" => 1, "高血圧症" => 2, "慢性腎臓病" => 2, "鉄欠乏性貧血" => 1, "脂質異常症" => 1, "狭心症" => 1, "花粉症" => 1} |
| F4 | PASS（単独の再実行） | pending: 実行しませんでした: 版の対応が無い項目がある: 収縮期（openEHR-EHR-OBSERVATION.blood_pressure.v2 at0004） |
| G1 | PASS | ["Body mass index", "判定"] |
| G2 | PASS（台本を直した） | ["収縮期\n テンプレート\n CardiologyEncounter\n"] … 台本の期待（patient_blood_pressure も出る）が誤り。OPT の名前は英語の「Systolic」 |
| H1 | PASS | 収縮期=134.0 拡張期=82.0 |
| H2 | PASS | flash=修正しました versions=["版 1（2026-11-26 02:03:03 UTC）", "版 2（2026-11-26 02:03:30 UTC）（この版）"] |
| H3 | PASS | flash=削除しました path=/compositions (修正前の記録 /patients/04415d1d-4b0a-44d9-bb35-1136768606d6) |
| H4 | PASS | records=17 |
| I1 | PASS | StructureDefinition openehr-problemlist-evaluation-problem-diagnosis-v1 |
| I2 | PASS | 200 CapabilityStatement |

A1 はビルドの成功（`naming to docker.io/library/anlage:latest`）。

## 台本の準備で見つけて直したもの（main に入れた）

| 見つけたこと | 直し | PR |
|---|---|---|
| Docker（production）では `demo:reset` が止まり、初期データを入れられない | `ANLAGE_ALLOW_DEMO_RESET=1` のときだけ許す（#168） | #169 |
| Docker（production）では、Basic 認証を与えても engine（AQL 照会・FHIR・openEHR REST）が 403 | Basic 認証を与えたときは engine を開ける（#174） | #175 |
| OBSERVATION を含む記録が、保存から 1 秒たつと修正できない（H の前提） | 元の記録のイベント時刻で組んで比べる（#171） | #172 |

## 台本を直したところ（台本の側の誤り）

- A3: 起動の途中は `502`（proxy が先に起きる）。`200` が出るまでくり返す、と書いた
- A5: テンプレートの画面の見出しは「テンプレートの取り込み」
- E1・E2: AQL 照会の画面は engine のもので、見出しは「AQL Query Console」、ボタンは「Run query」（英語）
- G2: patient_blood_pressure.v1 の収縮期は「収縮期」では出ない（OPT の名前が英語の「Systolic」）

## 既知の制限に足したもの（直さずに出す）

- 5a: 英語の OPT の項目は、日本語のパスカード検索では引けない（G2）
- 12a: 患者の画面の行の日時は、行を作った時刻で、記録日ではない（C2・D5。初期データでは、どの行も `demo:reset` の時刻）
- 12b: テンプレートを登録していない記録（初期データの紹介状 2 通）は、患者の画面とカルテ記録一覧に出ない（C2）
- 6a（#174 で足した）: Basic 認証を与えないと、Docker では engine が 403

## 次

- 人間が、同じ台本を画面で通す（裁定の 2 の 4）。F4 は、版の対応の表の血圧の行が pending のあいだは「版の対応が無い項目がある」が正しい結果
- 後片付け: 実行に使ったコンテナ `anlage` と volume `anlage-storage` は、この記録のあとに消した

## R2（2026-11-26）版上げ・患者の画面・血液内科の例のあとに、まっさらな Docker でもう一度通した（R-20261126-7 の受け入れの残り 1）

- 基準点: anlage main `3704add`（PR #178 の版上げ、#184 の患者の画面、#185 の出所の列、#187 の血液内科の例のあと）。この main から `docker build -t anlage .`
- 環境と道具は R1 と同じ（A2〜B2 は shell、A5〜I2 は headless Chrome）。volume は消してから新しく作った
- 台本を直したところ（この PR）:
  - F4: 版の対応の表の血圧の行が active になった（PR #159）ので、「6 行」だけを結果にした
  - F5（新）: 「テンプレートも表示する」で出所が template_id（既知の制限 18 の解消。PR #185 の文言）
  - H5（新）: 削除した記録が AQL にも出ない（既知の制限 13 の解消）。AQL 照会は数を `148` の形で出す
  - F3: 12 → 11 行。R-20261126-5 で DEMO-05 の紹介状の狭心症が「疑い」になり、未記入に入らなくなった（R1 の台本のままでは誤り）
  - A3: 起動の直後は `000`（つながらない）が出る
  - C2・D5・H4（#184）、B2・B4・E1（#187）は、それぞれの PR で直してある
- 1 回目（同じ日、新しい volume）は 28 行中 24 行が通った。落ちた 4 行は、台本の誤り（F3）と道具の誤り（F4 は描き直しの前の画面を読んだ、G2 は R1 で直した台本に道具が追随していなかった、H5 は数の書き方）。
  製品の側の不具合は無かった。台本と道具を直して、コンテナと volume を消し、2 回目を最初から通した。下は 2 回目
- **結果: 34 行すべて、台本どおり**（G2 は単独の再実行）

| # | 結果 | 出たもの |
|---|---|---|
| A1 | PASS | `docker build -t anlage .` が終わった（main `3704add`） |
| A2 | PASS | ab27e0ba8701 |
| A3 | PASS | 000 502 200 |
| A4 | PASS | 401 |
| A5 | PASS | h1=テンプレートの取り込み warning="参照実装です。認証がありません。実在の患者のデータを入れないでください。外から届く場所で動かさないでください。" |
| A6 | PASS | 患者:true テンプレート:true カルテ記録一覧:true パスカード検索:true クエリビルダー:true AQL 照会:true |
| B1 | PASS | demo:reset は production では実行しない（全データを消して入れ直す。実行するなら ANLAGE_ALLOW_DEMO_RESET=1 を与える） |
| B2 | PASS | templates=5 compositions=79 rm_compositions=84 |
| B3 | PASS | CardiologyEncounter／LabResultReport／ProblemList／bmi_calculation／COLNEC Patient Blood Pressure.v0 |
| B4 | PASS | DEMO-01,DEMO-02,DEMO-03,DEMO-04,DEMO-05,DEMO-06,DEMO-07,DEMO-08,DEMO-09 |
| C1 | PASS | notice="患者を選んでいません。保存するには、先に患者を選んでください。" save_button=false |
| C2 | PASS | records=18 first=CardiologyEncounter — 記録日 2026-10-15 |
| C3 | PASS | いまの患者: DEMO-01 |
| D1 | PASS | h2=テンプレートの取り込み: jp_referral version=登録版 v1.0.0／テンプレート版 0.2.0 |
| D2 | PASS | cards=6 登録版 v1.0.0／テンプレート版 0.2.0 |
| D3 | PASS | notice=false save=true |
| D4 | PASS | flash=保存しました h1=カルテ記録: jp_referral |
| D5 | PASS | records=19 first=jp_referral — 記録日 2026-11-26 |
| E1 | PASS | [["X病院", "2型糖尿病", "2026-08-03T00:00:00Z"], ["Y病院", "慢性腎臓病", "2026-11-26T06:20:39Z"], ["X病院", "狭心症", "2026-05-12T00:00:00Z"], ["X病院", "白血病", "2026-06-18T00:00:00Z"], ["X病院", "悪性リンパ腫", "2026-07-09T00:00:00Z"], ["X病院", "多発性骨髄腫", "2026-08-20T00:00:00Z"]] |
| E2 | PASS | [["Y病院", "慢性腎臓病", "2026-11-26T06:20:39Z"]] saved_at~2026-11-26T06:20:39Z |
| F1 | PASS | 2 行 ["148.0", "152.0"] |
| F2 | PASS | 9 行 |
| F3 | PASS | 11 行 {"2型糖尿病" => 3, "糖尿病性腎症" => 1, "高血圧症" => 2, "慢性腎臓病" => 2, "鉄欠乏性貧血" => 1, "脂質異常症" => 1, "花粉症" => 1} |
| F4 | PASS |  6 行 ["アーキタイプの版", "収縮期"] [["openEHR-EHR-OBSERVATION.blood_pressure.v1", "162.0"], ["openEHR-EHR-OBSERVATION.blood_pressure.v1", "158.0"], ["openEHR-EHR-OBSERVATION.blood_pressure.v1", "146.0"], ["openEHR-EHR-OBSERVATION.blood_pressure.v1", "142.0"], ["openEHR-EHR-OBSERVATION.blood_pressure.v2", "148 |
| F5 | PASS | 7 行 ["テンプレート", "プロブレム・診断名"] {"ProblemList" => 3, "jp_referral" => 4} |
| G1 | PASS | ["Body mass index", "判定"] |
| G2 | PASS（単独の再実行） | ["収縮期\n テンプレート\n CardiologyEncounter\n"] … 通しの実行では、検索の結果を読む前に画面が描き直され、道具が StaleElementReferenceError で止まった（道具の待ち方の誤り）。同じコンテナで G2 だけを、描き直しを待ってから読み直した |
| H1 | PASS | 収縮期=134.0 拡張期=82.0 |
| H2 | PASS | flash=修正しました versions=["版 1（2026-11-26 06:20:31 UTC）", "版 2（2026-11-26 06:20:58 UTC）（この版）"] |
| H3 | PASS | flash=削除しました path=/compositions (修正前の記録 /patients/b0451379-282b-4219-895a-de876dc763b5) |
| H4 | PASS | records=18 |
| H5 | PASS | [["148"], ["152"], ["138"]] |
| I1 | PASS | StructureDefinition openehr-problemlist-evaluation-problem-diagnosis-v1 |
| I2 | PASS | 200 CapabilityStatement |

- 後片付け: 実行に使ったコンテナ `anlage` と volume `anlage-storage` は、この記録のあとに消した
- 次: 人間が、同じ台本を画面で通す（ゲート報告）
