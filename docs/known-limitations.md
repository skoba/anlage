# 既知の制限（v0.2.0 の準備、2026-11-25）

Anlage は openEHR の**参照実装**で、診療の現場で使うための製品ではない。下は、main（`e003f5f` 時点）で実測した制限の一覧。
各項目に、根拠（ファイル・Issue・上流候補）を付けた。直す予定のものは Issue か `docs/upstream-candidates.md` にある。

## 使う前に知っておくこと

| # | 制限 | 根拠 |
|---|---|---|
| 1 | **認証と認可が無い。** 画面を開ける人は誰でも、全患者・全記録を見て、作り、修正し、削除できる。実在の患者のデータを入れない。環境変数を与えれば全体に Basic 認証をかけられる（README の「任意の Basic 認証」）が、利用者ごとの区別も記録の監査も無い | `app/controllers/` に認証の仕組みが無い。`docs/design/basic-auth-plan.md`（`skoba/anlage#163`） |
| 2 | 患者は患者 ID（と名前空間 `anlage`）だけを持つ。氏名・生年月日などの患者マスタ（PARTY）は無い | `docs/design/m3-plan.md` 7.2。openehr-rails 0.9.0 に PARTY のモデルが無い |
| 3 | （解消。2026-11-26、`skoba/anlage#161`）患者を選ばないと帳票を保存できない。番号はほかの項目の参照のために残す。#161 より前に保存した、患者に結び付かない記録は、そのまま残る | R-20261126-2 の 5、`docs/design/m3-plan.md` 7.5 の問い 4 |
| 4 | データベースは SQLite で、1 台で動かす前提。Docker のイメージは TLS の設定（`assume_ssl`・`force_ssl`）を切ってある。外に出すなら TLS を終端するプロキシの後ろに置く | `config/database.yml`、`config/environments/production.rb:28-31` |
| 5 | 画面の文言は日本語だけ | `docs/demo/ui-vocabulary.md` |
| 5a | テンプレートの項目名は OPT の言語のまま。patient_blood_pressure（英語の OPT）の項目は、パスカード検索で日本語（例「収縮期」）では引けず、英語（「Systolic」）で引ける | `spec/fixtures/opt/patient_blood_pressure.opt`（`docs/demo/opt-catalog.md`）。受け入れの台本 G2（`docs/reports/acceptance-v0.2.0-log.md`） |
| 5b | 日付の表示（患者の画面の記録日など）は日本時間に固定。アプリの時間帯は設定していない（UTC のまま）。表示の helper が、初期データの定数 `Demo::SampleCompositions::RECORDED_ZONE`（`Asia/Tokyo`）を使っている。時間帯を設定で選べるようにする件は、good first issue の候補 G7 | `app/helpers/patients_helper.rb` の `recorded_date`。R-20261126-12 の統括の読み直し |
| 6 | 用語マスター（ICD-10 対応標準病名マスターなど）は同梱しない。用語サービスにもつないでいない | CLAUDE.md 絶対規律 6（コンテンツ防火壁） |
| 6a | Docker（production）では、Basic 認証を与えないと、openehr-rails の engine（AQL 照会の画面、`/openehr/fhir`、`/openehr/v1`）が 403 を返す（gem の既定）。与えれば使える | openehr-rails 0.10.0 `app/controllers/openehr_rails/application_controller.rb:20-26`、`config/initializers/openehr.rb`（`skoba/anlage#174`） |
| 6b | Docker（production）で Basic 認証を与えずに起動すると、engine の画面と API は 403 になるが、anlage の画面（患者、帳票、カルテ記録、パスカード検索、クエリビルダー）は認証なしで開いたままになる。README の Docker の手順は、Basic 認証を与える形を先に書いている | `config/application.rb`（`OptionalBasicAuth` は両方の環境変数があるときだけかかる）。R-20261126-7 の統括の読み直し |

## 帳票と保存

| # | 制限 | 根拠 |
|---|---|---|
| 7 | 値集合の無い「コード化必須」の項目は、system と code の手入力になる（用語サービスが無いため）。実物の OPT での確認はまだ | `app/lib/opt/form_validator.rb` の `coded_manual_error`、Issue #82 |
| 8 | INSTRUCTION の ACTIVITY は `action_archetype_id` が既定値の `/.*/` で、timing を持たない | `app/lib/opt/composition_builder.rb` の `DEFAULT_ACTION_ARCHETYPE_ID`、Issue #30 |
| 9 | 必須の規則は「入れ物を書くなら必須」。入れ物の下限が 1 以上になる実物の OPT はまだ無く、その場合の判定は合成の spec でだけ確かめた | `docs/design/required-rule.md` |
| 10 | 登録済みのテンプレートの web_template は登録の時点で固定される。版を上げたあとに新しい規則（必須の規則・入れ物の情報など）を効かせるには `rake templates:rebuild_web_template` が要る | `lib/tasks/templates.rake` |
| 11 | 帳票の「実行時の振る舞い」（BMI の自動計算など）は `config/form_behaviors.yml` の安全な式だけ。GDL の評価器は無い | `config/form_behaviors.yml`、`docs/ideas-2027.md` |

## カルテ記録の修正と削除

| # | 制限 | 根拠 |
|---|---|---|
| 12 | 読み戻して組み直すと内容が変わる記録は修正できない。いまは jp_referral（INSTRUCTION、多段の CLUSTER、同じアーキタイプの 2 つめの ENTRY を読み戻せない） | `app/lib/opt/composition_editability.rb`、Issue #30 |
| 13 | （解消。2026-11-26、`skoba/anlage#177`）openehr-rails 0.11.0 で、削除した記録は AQL の結果と engine の EHR の画面から外れる。番号はほかの項目の参照のために残す。REST の GET で削除済みの記録の本文が返るのは gem の既知の制限（openehr-rails #85） | `docs/upstream-candidates.md` 28 項、`spec/requests/record_delete_spec.rb` |
| 14 | 削除の取り消し、版の巻き戻し、EHR の削除は無い | `docs/design/m3-plan.md` 7.6 |
| 12a | （解消。2026-11-26、`skoba/anlage#182`）患者の画面の行は、記録日（context/start_time）の新しい順に並び、記録日を出す。番号は残す | `app/views/patients/show.html.erb` |
| 12b | テンプレートを登録していない記録（初期データの紹介状。RM の側にだけ入る）は、カルテ記録一覧（`/compositions`）に出ない。患者の画面には出る（閲覧だけ。skoba/anlage#182） | `app/controllers/compositions_controller.rb` の `index`（原本の `compositions` から引く） |

## AQL と検索

| # | 制限 | 根拠 |
|---|---|---|
| 15 | AQL は最新の版だけを引く。`VERSION`・`ALL_VERSIONS` などの FROM は使えない | openehr-rails 0.9.0 `lib/openehr_rails/aql/query_validator.rb:21` |
| 16 | canonical のデータが混ざると、埋め込みの C_ARCHETYPE_ROOT のパスが AQL で合わないことがある | Issue #7 |
| 17 | パスカード抽出のレポート（未翻訳の疑いなど）は画面に出ない | Issue #13 |
| 18 | （解消。2026-11-26、`skoba/anlage#177`）openehr 2.6.1・openehr-rails 0.11.0 で `c/archetype_details/template_id/value` に AQL が届く。デモクエリ 5 は template_id で並記する。番号は残す。クエリビルダーの「文書名も表示する」と評価のゴールド a003 は、Composition 名（`c/name/value`）のまま（引く側と人間の判断） | `docs/upstream-candidates.md` 25 項、`spec/demo/cross_template_query_spec.rb` |
| 19 | openehr-rails の FHIR facade の Observation（`/openehr/fhir/Observation`）は、anlage では常に 0 件（1 件の取得は 404）。facade は scaffold した model（`Storable`）を `ResourceRegistry` から引き、実行時に登録したテンプレートの記録を見ない。StructureDefinition は anlage の入口（`/fhir/r5/StructureDefinition/:id`）が登録したテンプレートから作る。engine の `/openehr/fhir/StructureDefinition/:id` は gem の `OpenehrTemplate` を引くので 404 | openehr-rails 0.11.0 `app/controllers/openehr_rails/fhir_controller.rb`（`search`・`resolve`）、`lib/openehr_rails/fhir/resource_registry.rb`、`lib/openehr_rails/fhir/profile_repository.rb`。`app/controllers/fhir/profiles_controller.rb` の注釈。実測は `docs/design/m3-plan.md` 9.3（skoba/anlage#193） |
| 20 | openehr 2.6.1 では、日時（DV_DATE_TIME）の順序が月末で逆になることがある（31 日の昼すぎと、翌月 1 日の早い時刻など）。`magnitude` が 1 年を 365.24 日、1 か月を 30.42 日として数えるため。当たるのは、AQL 照会の画面に手で書く問いで、日時そのものの `ORDER BY`（例 `ORDER BY c/context/start_time`）と、`.../magnitude` を引く・比べる条件。値の文字列（`.../value`）を比べる条件と並べ替えは当たらない。anlage のクエリビルダー（日付の範囲は `.../value` の比較）、デモクエリ、評価のゴールド（`ORDER BY` を使わない）、患者の画面の並び（データベースの列）は当たらない。日時そのものに `>=` などを付けた条件（`WHERE c/context/start_time >= "…"`）は、この版では実行時の例外になる。直った openehr の版に上げたら、この行を消す | openehr-ruby の Issue #117（読み取り越境で読んだ。master で修正、未公開）。openehr 2.6.1・openehr-rails 0.11.0 での実測（2026-11-27）: `2026-01-31T12:00:00Z` と `2026-02-01T00:00:00Z` の記録で、`ORDER BY c/context/start_time` は 02-01 が先、`c/context/start_time/magnitude` は 63939297024.0 と 63939290111.99999（逆）。`ORDER BY …/value` と `WHERE …/value >= "2026-02-01T00:00:00Z"` は正しい。`DvDateTime#<=>` も `2026-01-31T12:00:00Z` を `2026-02-01T00:00:00Z` より後と答える |
