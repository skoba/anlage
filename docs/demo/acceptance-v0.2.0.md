# 受け入れの台本（公開 v0.2.0）

裁定 ID: R-20261126-2（2）。Issue: #173。この台本を、まっさらな Docker で最後まで通す。
各行は「操作」と「画面に出るはずの結果」の対。結果が違ったら、行の番号と、出た結果を書き留める。

- 値は合成で、患者は架空（`docs/design/sample-data-plan.md`）。実在の患者のデータを入れない
- 文言は `docs/demo/ui-vocabulary.md` の写し
- 下の `<pw>` は、自分で決めた長いパスワードに置き換える
- 実行の記録: `docs/reports/acceptance-v0.2.0-log.md`

## A. Docker での起動

| # | 操作 | 画面に出るはずの結果 |
|---|---|---|
| A1 | リポジトリの根で `docker build -t anlage .` | 最後に `naming to docker.io/library/anlage` が出て、終わる |
| A2 | `docker volume rm anlage-storage`（前の volume があれば。無ければ「no such volume」で構わない）のあと、`docker run -d --name anlage -p 8080:80 -e SECRET_KEY_BASE=$(openssl rand -hex 64) -e ANLAGE_BASIC_AUTH_USERNAME=demo -e ANLAGE_BASIC_AUTH_PASSWORD=<pw> -v anlage-storage:/rails/storage anlage` | コンテナの ID が 1 行出る |
| A3 | `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/up` を、`200` が出るまで数秒おきにくり返す | 起動の途中は `502`（前に立つ proxy が先に起きる）。起動すると `200`（`/up` に Basic 認証はかからない） |
| A4 | `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/patients` | `401` |
| A5 | ブラウザで http://localhost:8080/ を開き、利用者名 `demo` とパスワード `<pw>` を入れる | 見出し「テンプレートの取り込み」（テンプレートの画面）。左のナビの先頭に、地の色を変えて「参照実装です。認証がありません。実在の患者のデータを入れないでください。外から届く場所で動かさないでください。」 |
| A6 | 左のナビを上から順に押す（患者／テンプレート／カルテ記録一覧／パスカード検索／クエリビルダー／AQL 照会） | どの画面にも A5 の警告が出る。AQL 照会も開ける（403 にならない） |

## B. 初期データの投入

| # | 操作 | 画面に出るはずの結果 |
|---|---|---|
| B1 | `docker exec anlage bin/rails demo:reset` | 「demo:reset は production では実行しない（全データを消して入れ直す。実行するなら ANLAGE_ALLOW_DEMO_RESET=1 を与える）」で止まる |
| B2 | `docker exec -e ANLAGE_ALLOW_DEMO_RESET=1 anlage bin/rails demo:reset` | 最後の行が `templates=5 compositions=79 rm_compositions=84` |
| B3 | ナビ「テンプレート」 | カードが 5 枚（CardiologyEncounter、LabResultReport、ProblemList、bmi_calculation、patient_blood_pressure.v1） |
| B4 | ナビ「患者」 | 表に 9 行（DEMO-01〜DEMO-09。名前空間は anlage） |

## C. 患者を選ぶ

| # | 操作 | 画面に出るはずの結果 |
|---|---|---|
| C1 | ナビ「テンプレート」→ ProblemList の「帳票に入力」 | 注記「患者を選んでいません。保存するには、先に患者を選んでください。」。保存のボタンが無い |
| C2 | ナビ「患者」→ DEMO-01 | 見出し「患者: DEMO-01」。「カルテ記録」に 18 件、記録日の新しい順。先頭は「CardiologyEncounter — 記録日 2026-10-15」。紹介状のサンプル「jp_referral — 記録日 2026-08-03」も出る（テンプレート未登録。押すと閲覧の画面で、注記「この記録のテンプレートは登録されていません。閲覧だけです。」と項目の一覧） |
| C3 | 「この患者を選ぶ」 | ナビの下に「いまの患者: DEMO-01」と「選択を外す」 |

## D. 紹介状を帳票から入力して保存

| # | 操作 | 画面に出るはずの結果 |
|---|---|---|
| D1 | ナビ「テンプレート」→「ファイルを選択」→ `spec/fixtures/opt/jp_referral.opt` | 見出し「テンプレートの取り込み: jp_referral」、「アーキタイプ検出」の記録、「登録版 v1.0.0／テンプレート版 0.2.0」、ボタン「登録」 |
| D2 | 「登録」 | カードが 6 枚になり、jp_referral のカードに「登録版 v1.0.0／テンプレート版 0.2.0」 |
| D3 | jp_referral の「帳票に入力」 | 帳票。患者の注記は出ず、ボタン「保存」がある |
| D4 | 「サービス依頼」のサービス名に「精査」、「紹介元医療機関」の名称に「A診療所」、「紹介先医療機関」の名称に「Y病院」、「傷病名」の名称に「慢性腎臓病」を入れて「保存」 | flash「保存しました」、見出し「カルテ記録: jp_referral」 |
| D5 | ナビ「患者」→ DEMO-01 | 「カルテ記録」が 19 件。先頭が「jp_referral — 記録日 <今日>」 |

## E. 紹介先と紹介日で引く（AQL 照会）

| # | 操作 | 画面に出るはずの結果 |
|---|---|---|
| E1 | ナビ「AQL 照会」（見出しは engine の英語の「AQL Query Console」）の入力欄に、下の AQL（紹介先・傷病名・紹介日）を貼り、「Run query」 | 6 行: `X病院・2型糖尿病・2026-08-03T00:00:00Z`、`X病院・狭心症・2026-05-12T00:00:00Z`、`X病院・白血病・2026-06-18T00:00:00Z`、`X病院・悪性リンパ腫・2026-07-09T00:00:00Z`、`X病院・多発性骨髄腫・2026-08-20T00:00:00Z`、`Y病院・慢性腎臓病・<D4 で保存した時刻>` |
| E2 | 入力欄の AQL の末尾に `WHERE c/context/start_time/value >= "2026-09-01T00:00:00Z"` を足して「Run query」 | 1 行: `Y病院・慢性腎臓病・<D4 で保存した時刻>`（紹介日で絞れる） |

E1 の AQL:

```
SELECT i/protocol[at0008]/items[openEHR-EHR-CLUSTER.organisation.v1, '紹介先医療機関']/items[at0001]/value/value AS receiver,
       ev/data[at0001]/items[at0002]/value/value AS diagnosis,
       c/context/start_time/value AS referred_at
FROM EHR e CONTAINS COMPOSITION c[openEHR-EHR-COMPOSITION.request.v1]
     CONTAINS (INSTRUCTION i[openEHR-EHR-INSTRUCTION.service_request.v1]
               AND EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1])
```

## F. クエリビルダー

| # | 操作 | 画面に出るはずの結果 |
|---|---|---|
| F1 | ナビ「クエリビルダー」→「探したい項目」に「収縮期」→「検索」→ CardiologyEncounter の「収縮期」で「表示する項目に足す」と「条件に足す」→ 演算子「>=」、値「140」→「実行」 | 「2 行」。148.0 と 152.0 |
| F2 | ナビ「クエリビルダー」→「診断名」で検索 → ProblemList の「プロブレム・診断名」を「表示する項目に足す」→「診断確度」で検索 → 「条件に足す」→「確定」にチェック →「実行」 | 「9 行」 |
| F3 | F2 の条件の「未記入を含む」にチェック →「実行」 | 「12 行」（確定 9 と、確度を書かない紹介状 3: 2型糖尿病、狭心症、慢性腎臓病）。AQL に `OR NOT EXISTS` が出る |
| F4 | ナビ「クエリビルダー」→ F1 と同じ選択と条件で、「版をまたいで引く」にチェック →「実行」 | 版の対応の表（`config/version_mappings.yml`）の血圧の行が **pending** のあいだは「実行しませんでした: 版の対応が無い項目がある: 収縮期（openEHR-EHR-OBSERVATION.blood_pressure.v2 at0004）」。**active** なら、先頭の列「アーキタイプの版」つきで 6 行（v1 の 162・158・146・142、v2 の 148・152） |

## G. パスカード検索（別名を含む）

| # | 操作 | 画面に出るはずの結果 |
|---|---|---|
| G1 | ナビ「パスカード検索」→「BMI」で検索 | 先頭のカードが「Body mass index」（別名表の「BMI」の行で引く） |
| G2 | 「収縮期」で検索 | CardiologyEncounter の「収縮期」のカードが出る。patient_blood_pressure.v1 の収縮期は出ない（この OPT の名前は英語の「Systolic」。「Systolic」で検索すると出る。既知の制限 5a） |

## H. カルテ記録の修正と削除

| # | 操作 | 画面に出るはずの結果 |
|---|---|---|
| H1 | ナビ「患者」→ DEMO-01 → CardiologyEncounter の記録を 1 つ開く →「修正」 | 修正の帳票。前の値（収縮期・拡張期）が入っている |
| H2 | 収縮期を 1 だけ下げて「保存」 | flash「修正しました」。「版の履歴」に 2 行、2 行目に「（この版）」 |
| H3 | 同じ記録の画面で「削除」→ 確認「このカルテ記録を削除しますか？」で OK | flash「削除しました」。カルテ記録一覧に、その記録が無い |
| H4 | DEMO-01 の画面 | 「カルテ記録」が 18 件（H3 の記録が消えた） |

## I. FHIR の読み出し

| # | 操作 | 画面に出るはずの結果 |
|---|---|---|
| I1 | ナビ「テンプレート」→ ProblemList の「詳細」→「FHIR プロファイル」のリンク | JSON。`resourceType` が `StructureDefinition`、`id` が `openehr-problemlist-evaluation-problem-diagnosis-v1` |
| I2 | `curl -s -u demo:<pw> http://localhost:8080/openehr/fhir/metadata` | JSON。`resourceType` が `CapabilityStatement` |

## 後片付け

`docker rm -f anlage` と `docker volume rm anlage-storage`。
