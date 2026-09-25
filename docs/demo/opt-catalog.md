# OPT fixtureカタログ

`spec/fixtures/opt/`配下の全OPT fixtureを実測で列挙する。fixture悉皆・MANIFEST的な
記録はこのファイルに統合し、他所に分散させない。

## 特記: rails demo_assetsとAnlage fixtureの名称衝突に注意

openehr-railsの`demo_assets/templates/problem_list.opt`と、Anlageの
`spec/fixtures/opt/ProblemList.opt`は**別物**（大文字小文字以外は同名だが中身が違う）。
混同すると重大な誤りにつながるため必ず区別すること:

| | rails `problem_list.opt` | Anlage `ProblemList.opt` |
|---|---|---|
| sha256 | `6c0d5d4f582dd83d01064bd78132a5a4031b1b788583b3d48cb8fd26179ceb97` | `b821b98beebfba9e758cc0429a91bb98aedb7d50de684424f0eb58d51e4a47c1` |
| 言語 | en | ja |
| term_bindings/C_CODE_REFERENCE | 0件 | 1件（WP1カード1・WP2 value_set_bindingの根拠） |
| Anlageでの使用 | **未使用**（取り込んでいない） | WP0〜WP2で使用中 |

## カタログ本体

| ファイル | sha256 | 言語（実測） | 役割 | 状態 | 出所 |
|---|---|---|---|---|---|
| `CardiologyEncounter.opt` | `57e6e93ec301d5f4dda779285ca48646a5ba0dad7662622672b4fd67aa07736b` | ja | WP1/WP2 サンプルカード3（収縮期血圧）。term_bindings（SNOMED-CT）実例 | 凍結 | CKM公開archetype、Archetype Designer経由で人間作成（2026-08-22） |
| `LabResultReport.opt` | `414bbd49996f5dfd2da5a3374ced6ada7e7fc32405a883d8f51808bb00554743` | ja | WP1/WP2 サンプルカード2（検査値、埋め込みCLUSTER実例）。DV_QUANTITY制約は暫定（単位・値域なし） | 改訂待ち（単位・値域入り版を人間へ依頼中、`pathcards-schema-v1.md` 4節-3） | CKM公開archetype、AD経由で人間作成（2026-08-22） |
| `ProblemList.opt` | `b821b98beebfba9e758cc0429a91bb98aedb7d50de684424f0eb58d51e4a47c1` | ja | WP1/WP2 サンプルカード1（傷病名、C_CODE_REFERENCE/value_set_binding実例）。ローカルcode_list実例（at0073） | 凍結 | CKM公開archetype、AD経由で人間作成（2026-08-22） |
| `patient_blood_pressure.opt` | `9f1f679fcf9d2737d9f537b3e256f42c97e875c3fef9e835a54e9c1d415826e4` | en | 全spec一括緑化用fixture（`skoba/anlage#3`解消）。term_bindings（SNOMED-CT）4件・血圧archetype | 凍結 | openehr-rails demo_assets（commit `0028e0c32fc4331f51565d708f6e9f485ea315a3`、2026-07-29）からコピー |
| `bmi_calculation.opt` | `d80e2ea6bab02fef0d34035cae507887ee1fc21b0a304e1a7175324118c9baea` | en※ | `skoba/anlage#5`案Aシード用途（`openEHR-EHR-OBSERVATION.height.v2`実archetype構造）。LOINC code_binding実例 | 凍結（AQLのpath照会用途限定。ラベル翻訳検証には未使用） | openehr-rails demo_assets（commit `0f88392d7c890a39fa82bebf26f42410d5c9b9af`、2026-06-26）からコピー |
| `jp_referral.opt`（**登録済み v0.1**、dev DB id=5・`1.0.0`・active。`spec/fixtures/opt/` への fixture 化は `#23` (3) で） | `99d474f8ab86a9980cb6d997168b89a3eed6fd4e8f02a8217dbcd1ef936d62fa` | ja（実測。term_definitions は ja のみ・26 カード全て ja ラベル） | 診療情報提供書 v2（jp_referral）v0.1: 様式11 直写・narrative-first。13 埋め込みルート／10 アーキタイプ（COMPOSITION.request.v1 ⊃ SECTION.referral_details.**v0** ⊃ service_request／problem_diagnosis／story／clinical_synopsis ×2、organisation ×5・person ×3・address・electronic_communication）。骨格契約 `docs/design/referral-v2-inventory.md` **v2.1**（2026-09-25、§7 転記済み）。受入 goal `skoba/anlage#23` | **登録済み v0.1**（診断ドロップ済み。既知の欠落: 処方＝v0.2、患者 CLUSTER 未配置。抽出器の path 崩れ `#29`、保存経路 `#30`） | `skoba/openehr-templates-jp`@`8eebe0434f363deb71acb298f11cb1c70adbb77d`（`jp_referral.opt`・AD ソース `jp_referral.t.json` sha256 `7a6a92cb…2860`）。人間が Archetype Designer で新築（2026-09-21、AD 系）。ja 訳は翻訳プロジェクト Sprint A 由来（人間報告）。系譜元 `skoba/mml` `mml_referral.opt`（取り込み見送り: `docs/reports/referral-intake-log.md` R1・`docs/backlog.md` 8項） |

※ `bmi_calculation.opt`は言語宣言（archetypeレベル）はenだが、`at0013`（判定）のterm_definitionsのみja訳が混在している（`spec/fixtures/opt/bmi_calculation.opt:1678`実測。WP4評価データq09「BMI判定」がこのjaラベル経由で成立することを確認、`docs/reports/wp4-log.md`参照）。

## 状態の凡例

- **凍結**: 現行のまま使用継続。改訂予定なし
- **改訂待ち**: 人間からの改訂版供給を待っている（差し替え予定あり）
- **新規予定**: まだ存在しないが、供給を依頼中の新規fixture
- **AD 組み立て中**: 人間がArchetype Designerで組み立て中の新規テンプレート（初版OPTの納品待ち。納品後は診断ドロップ→fixture化の順で本表を更新する）
- **登録済み v0.1**: 初版 OPT を dev へ診断ドロップ済み（検収レポートあり）。fixture 化（`spec/fixtures/opt/`・golden）は未了で、次版 OPT の納品で差し替わり得る

## 未消化タスクの統合先

- fixture悉皆・MANIFEST的な確認作業は本カタログの更新で消化する（別文書は作らない）
- gem側（openehr-rails）自身のdemo_assets MANIFEST整備は、Anlageの管轄外。12月世界公開準備のbacklogへ委ねる（`docs/backlog.md`参照）

## 運用注記: パスカード生成には登録経路が影響する

`Template.build_from_opt_xml(...).save`等の直接model save（`TemplatesController#create`
を経由しない登録）は、`Opt::PathcardExtractor`のフックが発火しないため`templates.pathcards`
が未生成のまま残る（`skoba/anlage#12`, WP3 explore実測、`docs/reports/wp3-log.md` R1）。
実演相当のパスカード生成を確認したい場合は、必ずドロップゾーン経由（`POST /templates`）で
登録すること。開発DBで生成漏れが見つかった場合は`rake pathcards:backfill`で補完できる。
