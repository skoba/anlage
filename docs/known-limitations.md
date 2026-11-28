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
| 11 | 帳票の「実行時の振る舞い」（BMI の自動計算など）は `config/form_behaviors.yml` の安全な式だけ（いまは YAML の軽い定義を優先し、GDL2 が普及した時点で乗り換える。R-20261127-16） | `config/form_behaviors.yml`、`docs/ideas-2027.md` |

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
| 19 | （解消。2026-11-28、openehr-rails 0.14.1 と `OpenehrRails::Fhir.template_source`。R-20261127-30・R-20261128-1）FHIR の facade（`/openehr/fhir/Observation`・`Condition`）が、anlage が実行時に登録したテンプレートの記録を見ず、いつも 0 件だった件。いまは、動いているテンプレート（template_id ごとに 1 つ）を `config/initializers/openehr.rb` で渡し、初期データの Observation と Condition が出る。facade が出す値の決まりは 24。engine の `/openehr/fhir/StructureDefinition/:id` は gem の `OpenehrTemplate` を引くので、いまも 404（プロファイルは anlage の入口 `/fhir/r5/StructureDefinition/:id`）。番号はほかの文書の参照のために残す | `spec/requests/fhir_runtime_records_spec.rb`（つなぐ前は 3 件とも 0 件で落ちた）。openehr-rails 0.14.1 `lib/openehr_rails/fhir/template_source.rb`（読み取り越境、`v0.14.1` = `51977db`） |
| 20 | （解消。2026-11-27、openehr 2.9.0 への版上げ。R-20261127-20 の 1）日時（DV_DATE_TIME）の順序が月末で逆になる件（openehr 2.6.1 の `magnitude` が 1 年を 365.24 日、1 か月を 30.42 日として数えていた）。日時そのものに `>=` などを付けた条件の例外は、残るので 22 に分けた。番号はほかの文書の参照のために残す | openehr-ruby の Issue #117（2.9.0 で修正）。`spec/lib/aql_date_time_order_spec.rb`（openehr 2.6.1 で 3 件とも落ち、2.9.0 で通る）。クエリビルダーの「日時の項目での並べ替えは、まだ使えない」の文言はこの番号を指している（引く側の R-20261127-32 で使えるようにする） |
| 21 | （患者の画面 U1 で入る）検査の値の系列は、分析名（LabResultReport の at0024）の文字列が完全に同じものだけを 1 つにまとめる。分析名は自由記述なので、表記がゆれる（「HbA1c」と「ＨｂＡ１ｃ」など）と系列が分かれる。本来は、コード（用語。例: JLAC）で分ける | `docs/design/u1-patient-chart-plan.md` の「承認と回答」1。R-20261127-13 |
| 22 | AQL 照会の画面に手で書く問いで、日時そのもの（DV_DATE_TIME）に `>=` などを付けた条件（`WHERE c/context/start_time >= "2026-02-01T00:00:00Z"`）は、実行時の例外になる。値の文字列（`.../value`）を比べる条件は動く（ただし文字列の比較なので、時刻帯の書き方がそろっていないと、時刻の順と食い違う）。anlage のクエリビルダー、デモクエリ、評価のゴールドは、この形を使わない | openehr-ruby の Issue #134（読み取り越境で読んだ。未修正）、#135（`…/value` の比較が文字列の比較）。openehr 2.9.0・openehr-rails 0.12.0 での実測（2026-11-27）: `2026-01-31T12:00:00Z` と `2026-02-01T00:00:00Z` の記録で、上の条件は `NoMethodError: undefined method 'magnitude' for an instance of String` |
| 23 | 部分的な日時（日まで、月まで、分まで）を OBSERVATION のイベントの時刻として保存すると、患者の画面では、その時刻ではなく記録の開始時刻（context の start_time）の日の列に出る。openehr-rails 0.15.0 から、記録した文字はそのまま残り、REST・FHIR もその文字を返す（0.14.1 までは `2026-03-01T00:00:00Z` に補って返した）。anlage の側で記録の時刻を読む `Opt::RecordedTime`（`Time.iso8601`）が、秒までそろった値しか読めないため。時刻帯の無い日時（`2026-03-01T09:30:00`）は、`Opt::RecordedTime` ではプロセスの時刻帯として読む（gem の並べ替えと比較は UTC として読む。openehr-rails 0.14.1 から）。anlage の帳票はイベントの時刻を入力させない（保存した時刻か、サンプルデータの記録日を入れる。`Opt::CompositionBuilder` の `recorded_at`）ので、帳票からは当たらない。部分的な日時をどの日の列に出すかは、記録の時刻帯の計画（R-20261128-16 の 4）で決める | openehr-rails 0.15.0 での実測（2026-11-28）: committer の編集のブロックでイベントの時刻を書き換えて保存すると、`2026-03-01`・`2026-03`・`2026-03-01T09:30`・`2026-03-01T09:30:00`・`2026-03-01T09:30:00+09:00` は、`to_canonical_hash` でも REST でも書いた文字のまま読み戻る。`Opt::RecordedTime.of` は、はじめの 3 つで nil、`2026-03-01T09:30:00` は `+0900`（手元の WSL の時刻帯）。openehr-rails の Issue #121（0.15.0）、#109（0.14.1）。`spec/requests/patient_chart_spec.rb` の「日までの値」「月までの値」の例 |
| 24 | FHIR の facade（`/openehr/fhir/Observation`・`Condition`）が出す値のうち、記録に無いもの・FHIR の決まりに合わないもの: Condition の `clinicalStatus` は facade が置く（問題・診断のアーキタイプに臨床の状態が無いので、解決の日時〔at0030〕が無ければ `unknown`、あれば `inactive`）。`verificationStatus` はアーキタイプの at-code（例 `at0076`「確定」、system `local`）のままで、R5 の `condition-ver-status` に合わない。数量は記録の数のまま（`148.0`。患者の画面の表示の決まり〔精度を作らない〕は効かない）。INSTRUCTION（依頼と紹介状）は、どのリソースとしても出ない。facade は書き込み（`POST /openehr/fhir/Observation`）を、実行時に登録したテンプレートでは 422 で断る | openehr-rails 0.14.1 の README「Condition: values the facade sets, and known limitations」「Templates registered at runtime」（読み取り越境、`v0.14.1` = `51977db`）。初期データでの実測（2026-11-28）: DEMO-01 の Condition 3 件、Observation 26 件。Observation の日時は `effectiveDateTime`（例 `2026-01-15T00:00:00Z`）、Condition の発症日は `onsetDateTime`（`2018-04-01`）で、どちらも FHIR の dateTime の形 |
