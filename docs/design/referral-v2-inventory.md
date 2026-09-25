# 診療情報提供書テンプレート v2（jp_referral）— 骨格契約

- 版: **v2.1（2026-09-25）**。v2（2026-09-04、出典 `referral-v2-inventory-v2.xlsx`: 三面表・人間レビュー完了 OK 17 / 修正 9 / 不要 3 / 未記入 0）の §7 空欄を、jp_referral **v0.1** 初版 OPT の Anlage 診断ドロップ（`docs/reports/referral-intake-log.md` R4〜R6、`skoba/anlage#23` (1)(2)）から転記したもの
- 状態: **正典**。§2 は v0.1 の AD 実装を正とした実測骨格（v2 の設計骨格からの差分は §3.1・§10 に明記）。次版は v0.2 納品時（§10 段階付け）
- 実装物: `skoba/openehr-templates-jp`@`8eebe0434f363deb71acb298f11cb1c70adbb77d`（`jp_referral.opt` sha256 `99d474f8ab86a9980cb6d997168b89a3eed6fd4e8f02a8217dbcd1ef936d62fa`、AD ソース `jp_referral.t.json` sha256 `7a6a92cb101e78f45c3ab66128e6c4d6100312d13678d40592f98307b2dd2860`）。template_id `jp_referral`、言語 ja、13 埋め込みルート・10 アーキタイプ（人間が Archetype Designer で新築。ja 訳は翻訳プロジェクト Sprint A 由来——人間報告）
- 系譜元: `skoba/mml` `openEHR/templates/mml_referral.opt`（Ocean TD 2.6 世代・23 アーキタイプ・診断ドロップ 136 カード）。jp_referral は改訂ではなく **新築**（別 template_id）
- 検収済み要件源: 療担則別紙様式11 / MML 紹介状モジュール / JP-CLINS v1.13.0 `referral-doc.html`（2026-08-31 生成）

## 0. 位置づけ

本テンプレート群の設計は、共有臨床モデルからの多規格導出（Huff／CIMI の系譜）を、二層モデリングの乱立耐性——テンプレートは現場要件で分岐してよいが、アーキタイプ層でクエリの統一性を保証する——の上に実装するものである。**単一性の契約はテンプレートではなく骨格（概念→アーキタイプの決定集合）に置く。** 本文書がその骨格契約である。

## 1. 設計原則（契約）

1. **臨床モデルが意味の源。交換規格（MML / JP-CLINS / 様式11）は要件源かつ射影先であり、設計の鋳型ではない。** 交換規格の置き場から逆設計しない。
2. **骨格契約**: 概念ごとのアーキタイプ選定集合を正典とする。将来 JP-CLINS プロファイル版 OPT を分岐する場合もこの集合を共有する（§9）。
3. **横串一貫性 > 局所純度**: 文書横断で同一概念に同一アーキタイプ（例: 主訴 = reason_for_encounter）。
4. **ENTRY 型判定則**: 観察・報告された事実 → OBSERVATION（story, exam, lab）／臨床家の判断・要約 → EVALUATION（diagnosis, *_summary）／意図・指示 → INSTRUCTION。主訴は「担当医が主と判断した訴え」なので EVALUATION。
5. **再利用部品は役割文脈まで指定**: `アーキタイプ [(occurrences)] @ 充填先[SLOT]`。要素は `アーキタイプ / 要素名`。
6. **必要集合であって和集合ではない**: 三源のいずれにも要件が無い構造化は骨格に入れず、**拡張予約**（選定済み・未実装）として記録する。
7. **帳票は骨格からの射影**: 帳票に無い要素の存在は骨格の欠陥ではない（主訴は様式11 では症状経過欄へ、JP-CLINS では 340 へ、射影規則で畳む）。
8. **写像表は IG 別**: 汎用 FHIR 向けと JP-CLINS 向けは別表（例: 紹介目的は汎用では ServiceRequest.reasonCode、JP-CLINS では Encounter.reasonCode）。
9. **出所戦略**: feeder_audit をインジェスト必須項目とし、テンプレート分岐時は template_id 判別を併用。

## 2. 節骨格（v0.1 実測。様式11 の欄が節として現れる）

v0.1（様式11 直写・narrative-first）の実配置。アーキタイプ名は現行 CKM 名へ訂正済み（v2 の `COMPOSITION.referral`→`COMPOSITION.request.v1`、`INSTRUCTION.request-referral`→`INSTRUCTION.service_request.v1`、`CLUSTER.individual_professional`／`individual_personal`→`CLUSTER.person.v1`（+ structured_name／address／electronic_communication の下位 CLUSTER）、`SECTION.referral_details`→`.v0`）。角括弧はスロットの at-code（AD ソース `jp_referral.t.json` の overlay node id から。OPT 1.4 はスロット id を保持しないので OPT／パスカードからは読めない）。「」は AD が at0000 に与えた ja 名（RM インスタンスでは `name/value`）。

```
COMPOSITION.request.v1  (template_id: jp_referral)
├─ context/other_context[at0001]: items[at0042] Extension スロットのみ（未充填。患者 CLUSTER は v0.1 未配置）
└─ content: SECTION.referral_details.v0「紹介状の詳細情報」 (0..1)
    ├─ items[at0001] INSTRUCTION.service_request.v1「サービス依頼」 (0..1)
    │    activities[at0001]/description[at0009]:
    │      items[at0121] サービス名 (1..1, DV_TEXT)            ← 依頼内容（No.20 Service requested）
    │      items[at0062]「紹介目的」(0..*, DV_TEXT)             ← 紹介目的（No.8。at0064 は未使用、§3.1）
    │      items[at0150] 備考 (0..1, DV_TEXT)
    │    protocol[at0008]:
    │      items[at0010] 依頼者オーダー識別子 / items[at0011] 受領者オーダー識別子
    │      [at0141 Requester] CLUSTER.organisation.v1「紹介元医療機関」(0..1)          ← 紹介元（No.3）
    │           ⊃ [at0005] CLUSTER.address.v1「住所」/ [at0022] CLUSTER.electronic_communication.v1「電子的な連絡先」
    │           ⊃ [at0002] CLUSTER.person.v1「医師」(0..1): items[at0001] 氏名       ← 紹介元医師（No.4）
    │      [at0142 Receiver]  CLUSTER.organisation.v1「紹介先医療機関」(0..*)          ← 紹介先（No.1）
    │           ⊃ [at0017] CLUSTER.organisation.v1「診療科」(0..1): 名称/識別子/役割/コメント   ← 診療科（No.1 部門）
    │                ⊃ [at0002] CLUSTER.person.v1「担当医」(0..1): 氏名/コメント          ← 紹介先担当医（No.2）
    ├─ items[at0002] EVALUATION.problem_diagnosis.v1「傷病名」(0..1): data[at0001]/items[at0002] (1..1, DV_TEXT、束縛なし)
    ├─ items[at0002] OBSERVATION.story.v1「既往歴及び家族歴」(0..1): data[at0001]/events[at0002]/data[at0003]/items[at0004] 病歴の記述
    ├─ items[at0002] EVALUATION.clinical_synopsis.v1「症状経過及び検査結果」(0..1): data[at0001]/items[at0002] 要約
    └─ items[at0002] EVALUATION.clinical_synopsis.v1「治療経過」(0..1): data[at0001]/items[at0002] 要約
```

**紹介先・紹介元の配置**: COMPOSITION context ではなく **service_request の protocol[at0008]**（Requester at0141 / Receiver at0142 スロット）に置かれている。AD 実装を正とする（v2 §2 の設計どおり。context 配置ではない）。

**判別の原理（v2.1 で改定。2026-09-25 人間裁定で確定: name 述語を安定識別子として採用し、AD が at0000 に与えた ja 名を凍結する）**: 同一アーキタイプの複数出現（organisation ×5、person ×3、clinical_synopsis ×2）は AD ソースではスロット役割（at0141／at0142、at0017、at0002）で区別されるが、OPT 1.4 と RM インスタンスでは両 organisation が同じ `protocol[at0008]/items` 属性に並び、残る判別子は **`name/value`（AD が at0000 に与えた ja 名）と入れ子構造**だけである（R6 実測: AQL は `items[openEHR-EHR-CLUSTER.organisation.v1, '紹介先医療機関']` の name 述語で引く）。v2 の「名前制約に依存しない」は v0.1 では成立しない。名前を安定識別子として凍結するか、v0.2 で構造判別（例: 紹介先を Receiver スロット固有の入れ子で固定）へ寄せるかは §10 の裁定事項。

## 3. 決定表（概念 → アーキタイプ）

| No | 概念 | 骨格（openEHR） | 状態 | JP-CLINS（v1.13.0） | 様式11 |
|---|---|---|---|---|---|
| 1 | 紹介先医療機関・診療科 | CLUSTER.organisation (1..1) @ request-referral protocol/receiver | 実在 | JP_Organization_eCS（機関・診療科は別 Organization） | 紹介先医療機関名 |
| 2 | 紹介先担当医 | CLUSTER.individual_professional (0..1) @ 同 receiver（機関と兄弟・任意） | 実在 | JP_Practitioner_eCS | 担当医 |
| 3 | 紹介元医療機関 | CLUSTER.organisation @ request-referral protocol/requester | 実在 | JP_Organization_eCS | 紹介元 |
| 4 | 紹介元医師 | CLUSTER.individual_professional @ 同 requester | 実在 | JP_Practitioner_eCS | 医師氏名 |
| 5 | 患者基本情報 | CLUSTER.individual_personal @ COMPOSITION.referral other_context/patient SLOT | 実在（職業要素は実測待ち） | JP_Patient_eCS | 患者欄 |
| 6 | 紹介日 | COMPOSITION context/start_time | 実在 | Composition.date | 年月日 |
| 7 | 傷病名 | EVALUATION.problem_diagnosis @ SECTION[傷病名・主訴]（ICD-11 referenceSetUri 束縛） | 実在 | JP_Condition_eCS @ 340 | 傷病名 |
| 8 | 紹介目的 | request-referral / items[at0064]（記述）+ items[at0062]（コード 0..1） | 実在 | JP_Encounter_eCS.reasonCode @ 950 | 紹介目的 |
| 9 | 主訴 | EVALUATION.reason_for_encounter / Presenting problem @ SECTION[傷病名・主訴] | 実在 | JP_Condition_eCS @ 340（主訴側。FHIR は S/A を区別しない） | （症状経過に包含） |
| 10 | 既往歴 | story（narrative・主）+ problem_diagnosis (0..*) + problem_qualifier @ SECTION[既往歴・家族歴] | 実在（qualifier 追加） | JP_Condition_eCS @ 370 + section.text | 既往歴及び家族歴 |
| 11 | 家族歴 | EVALUATION.family_history @ SECTION[既往歴・家族歴] | 実在 | JP_FamilyMemberHistory_eCS | 同上 |
| 12 | 症状経過（現病歴） | OBSERVATION.story @ referral_details Details | 実在 | JP_Condition_eCS @ 360 + section.text | 症状経過及び検査結果 |
| 13 | 検査結果 | OBSERVATION.laboratory_test_result @ referral_details Details | **追加要** | JP_Observation_LabResult_eCS | 同上 |
| 14 | 治療経過 | EVALUATION.clinical_synopsis @ referral_details Details | 実在 | JP_DocumentReference @ 330 | 治療経過 |
| 15 | 現在の処方 | SECTION.medication_order_list ⊃ INSTRUCTION.medication_order | **追加要** | JP_MedicationRequest_eCS @ 430 | 現在の処方 |
| 16 | アレルギー・不耐性 | EVALUATION.adverse_reaction_risk @ SECTION[既往歴・家族歴] | **追加要** | JP_AllergyIntolerance_eCS（節非依存） | （備考扱い） |
| 17 | 感染症情報 | EVALUATION.infectious_disease_summary @ SECTION[既往歴・家族歴]（既定・反転可） | **追加要**（ID・版 実測待ち） | JP_Condition_eCS @ 340 + 根拠 JP_Observation_LabResult_eCS（二部写像） | なし |
| 18 | 生活歴（narrative） | EVALUATION.social_summary @ SECTION[既往歴・家族歴] | **追加要** | JP_Observation_Common | なし |
| 20 | 依頼内容 | request-referral / Service requested 要素【暫定】 | 実在 | （eReferral に ServiceRequest なし） | （紹介目的に包含） |
| 21 | 添付資料 | CLUSTER.multimedia / citation | 実在 | JP_DocumentReference・JP_Bundle_eDischargeSummary | 現物添付 |
| 22 | 備考 | free_text @ SECTION[備考] | 実在 | セクション 220 | 備考 |

追加要（core）は 6 件: laboratory_test_result / medication_order / adverse_reaction_risk / infectious_disease_summary / social_summary / problem_qualifier（CLUSTER）。いずれも CKM 実在、新規設計はゼロ。


### 3.1 v0.1 実測との突合（決定表 → 実装）

| No | 概念 | v0.1 実装 | 判定 |
|---|---|---|---|
| 1 | 紹介先医療機関・診療科 | organisation「紹介先医療機関」@ protocol[at0008] Receiver(at0142) ⊃ [at0017] organisation「診療科」 | 一致（部門は**入れ子の独立 organisation**。ただし at0017「追加の詳細情報」スロット経由——at0021「親組織」の逆向きではない） |
| 2 | 紹介先担当医 | person「担当医」@ 診療科 ⊃ [at0002] | 一致（individual_professional ではなく CLUSTER.person.v1） |
| 3 | 紹介元医療機関 | organisation「紹介元医療機関」@ protocol[at0008] Requester(at0141) ⊃ address／electronic_communication | 一致 |
| 4 | 紹介元医師 | person「医師」@ 紹介元医療機関 ⊃ [at0002] | 一致（CLUSTER.person.v1） |
| 5 | 患者基本情報 | **未配置**（other_context[at0001] は Extension at0042 のみ） | v0.2 以降（職業要素は未確定のまま） |
| 6 | 紹介日 | context/start_time（RM 固有、OPT に制約なし） | 一致 |
| 7 | 傷病名 | problem_diagnosis「傷病名」at0002（DV_TEXT、**ICD-11 束縛なし**、term_bindings 0） | 一致（束縛は v0.2 で追加要） |
| 8 | 紹介目的 | service_request at0062「紹介目的」(DV_TEXT 0..*) | **裁定済み（2026-09-25）: at0062 改名使用で確定**。v2 の at0064＋at0062 案は取り下げ（コード化理由は将来 at0062 の DV_CODED_TEXT 化で扱う） |
| 9 | 主訴 | **未配置**（reason_for_encounter 無し） | v0.2 |
| 10 | 既往歴 | story「既往歴及び家族歴」at0004（narrative のみ） | 一致（narrative-first。problem_diagnosis + problem_qualifier の構造化は v0.3） |
| 11 | 家族歴 | story「既往歴及び家族歴」に包含（family_history 無し） | v0.3 |
| 12 | 症状経過（現病歴） | **clinical_synopsis「症状経過及び検査結果」** | **裁定済み（2026-09-25）: clinical_synopsis で確定**（様式11 直写＝欄が一つの叙述。判定則 4 の例外として記録。v2 の story 案は取り下げ） |
| 13 | 検査結果 | 同上の narrative に包含 | v0.3（laboratory_test_result 構造化） |
| 14 | 治療経過 | clinical_synopsis「治療経過」 | 一致 |
| 15 | 現在の処方 | **未配置** | v0.2（既知の欠落） |
| 16 | アレルギー | **未配置** | v0.2 |
| 17 | 感染症 | **未配置** | v0.3 |
| 18 | 生活歴 | **未配置** | v0.3 |
| 20 | 依頼内容 | service_request at0121「サービス名」(1..1) | 一致（**at-code 確定**） |
| 21 | 添付資料 | 未配置（multimedia／citation 無し） | 要件出現時 |
| 22 | 備考 | service_request at0150「備考」 | v2 の SECTION[備考]/free_text とは別配置（依頼の備考として） |

## 4. 拡張予約・不採用・削除

| 区分 | 項目 | 選定 |
|---|---|---|
| 拡張予約（要件出現時に導入・選定済み） | 喫煙歴 | EVALUATION.tobacco_smoking_summary |
| 〃 | 飲酒歴 | EVALUATION.alcohol_consumption_summary.v1 |
| 〃 | 薬物使用歴 | EVALUATION.substance_use_summary（喫煙・飲酒以外） |
| 〃 | 曝露歴（環境・職業因子） | EVALUATION.exposure |
| 不採用（三源に要件なし。Details SLOT で受入可能なので要件出現時に再考） | 身体所見 / 画像所見 | OBSERVATION.exam / imaging_exam |
| 不採用（既定・反転可） | 経過記録（SOAP 断片） | progress_note（治療経過は clinical_synopsis が担う） |
| 削除 | 人種 | CLUSTER.race（日本文脈で不要） |

## 5. 系譜ノート（mml_referral → jp_referral）

| 処遇 | 対象 |
|---|---|
| 再配置（意味論的訂正） | 紹介目的: reason_for_encounter → request-referral at0064/at0062（第1号）／主訴: → reason_for_encounter（第2号） |
| 継承 | COMPOSITION.referral・SECTION.referral_details・request-referral・problem_diagnosis・story×2・clinical_synopsis・family_history・medication_order_list・multimedia・citation・free_text・organisation/individual 系 |
| 予約 | exposure |
| 削除 | race |
| 不採用（既定） | progress_note |
| 旧資産の指紋（受け入れポリシー項目 7 参照） | ja 宣言 × en ラベル混在／擬似特殊化命名（-mml, -japan）／同一 v1 内の改版ドリフト（at0027 配置ずれ・request 親子のスロット矛盾） |
| 実装リポジトリ（v2.1 追加） | `skoba/openehr-templates-jp`（AD プロジェクト `jp_referral.t.json` = ADL2 テンプレート＋overlay 13 件、および OPT 1.4 書き出し `jp_referral.opt`）。版は同リポジトリのコミット SHA で固定する |
| アーキタイプ ja 訳の出所（v2.1 追加、人間報告） | 翻訳プロジェクト Sprint A（`openehr-japanese-translation`）。v0.1 の 10 アーキタイプは term_definitions が ja のみ（en 無し）、パスカード 26 枚とも ja ラベル・説明あり（未翻訳疑い 0、AD 生成プレースホルダ「*…(en)」0） |

## 6. 写像方針

- **様式11 射影**: 節＝欄で 1:1。主訴は症状経過欄へ、生活歴・アレルギー・感染症は既往歴及び家族歴欄または備考へ（射影規則で確定）。
- **JP-CLINS 写像**（別表・IG v1.13.0）: 節単位で 340/370/360/330/430/220 と対応。referral_details は 950/360/330/検査結果へ扇状展開。SECTION[既往歴・家族歴] からは **アーキタイプ種別をキー**に 370／家族歴／AllergyIntolerance／Observation_Common へ展開。ENTRY 型非対称の注記: FHIR は主訴を Condition、社会歴を Observation で表す。
- **MML 写像**: mml_referral の構造がほぼそのまま（薄い写像）。再配置 2 件のみ要変換。
- **インジェスト二水準**: JP-CLINS「NoEntry」作例に倣い、narrative 水準（section.text → story / at0064 等）と構造化エントリ水準（entries → 各アーキタイプ）の両方を受ける。

## 7. AD 実測（v2.1 で転記済み）

出所: jp_referral v0.1 の診断ドロップ（`docs/reports/referral-intake-log.md` R4）。ELEMENT の at-code は抽出パスカード `identity.at_code` から、スロット at-code は OPT 1.4 に残らないため AD ソース `jp_referral.t.json` の overlay node id（`at0141.1` 等）から転記した。

| 空欄項目（v2） | 転記値（v0.1） |
|---|---|
| SLOT protocol/receiver | service_request.v1 `protocol[at0008]` **at0142**（Receiver）→ organisation「紹介先医療機関」(0..*) |
| SLOT protocol/requester | 同 **at0141**（Requester）→ organisation「紹介元医療機関」(0..1) |
| SLOT referral_details Details | referral_details.v0 `items` **at0002**（problem_diagnosis／story／clinical_synopsis ×2 が充填）。service_request は **at0001** スロット |
| SLOT other_context/patient | **未配置**（request.v1 `other_context[at0001]/items[at0042]` Extension スロットのみ） |
| 要素 Service requested（No.20） | service_request.v1 **at0121**「サービス名」DV_TEXT 1..1 |
| 紹介目的（No.8） | service_request.v1 **at0062**「紹介目的」DV_TEXT 0..*（at0064 未使用） |
| 傷病名（No.7） | problem_diagnosis.v1 **at0002** 1..1。v0.1: DV_TEXT・束縛なし → **v0.2: 代替 [DV_TEXT, DV_CODED_TEXT]、主型 DV_CODED_TEXT、ICD-11 MMS の `referenceSetUri`（value_set_binding）**（R10） |
| 発症日時（v0.2 追加） | problem_diagnosis.v1 **at0077**「発症日時」DV_DATE_TIME 0..1（`data[at0001]/items[at0077]`） |
| 診断確度（v0.2 追加） | problem_diagnosis.v1 **at0073**「診断確度」DV_CODED_TEXT（ローカル code_list: at0074 疑い／at0075 推定／at0076 確定。`spec/demo/` の MATCHES クエリ 2 と同じ要素） |
| 新規 6 アーキタイプの ID・版・公開状態・ja 訳 | **v0.1 未収録**（laboratory_test_result／medication_order／adverse_reaction_risk／infectious_disease_summary／social_summary／problem_qualifier）。§10 の段階へ |
| individual_personal の職業要素（No.5） | 患者未配置のため **未確定**（v0.1 は person.v1 系を使用、individual_personal は不使用） |
| organisation の部門表現（No.1） | **入れ子の独立 organisation**: 紹介先医療機関 ⊃ [at0017 追加の詳細情報] organisation「診療科」⊃ [at0002 連絡担当者] person「担当医」 |

パスカード側の注意: 抽出器は SECTION 配下の埋め込みルートの path を `items[at0000]` で書き出す（`skoba/anlage#29`）。at-code は正しいが、path 文字列をそのまま AQL に転用できない。

## 8. 受入検証計画（Step 4・凍結前は手動写像 1 事例ずつ）

- MML 側: 実 MML 紹介状 1 通 → Composition（手動写像）→ 同一 AQL で引けること
- JP-CLINS 側: 準拠 Bundle 1 通（NoEntry 作例可）→ 同上
- 統合 spec: 「両源から同じ AQL で引ける」を jp_referral の受入条件とする。変換器の自動化（fhirbridge / MML パーサ）は 12 月以降

**補記（2026-09-25 裁定・デモ役割の縮退）**: 統合 spec は Anlage のフォーム保存経路ではなく**直接コミット経路**（手写像 canonical JSON → `OpenehrRails::Rm::CompositionCommitter` → AQL）で組む（`skoba/anlage#30` はフォーム経路の課題として別扱い）。ただし RM 側の実体化が SECTION／INSTRUCTION を扱えない（`docs/upstream-candidates.md` **15 項**）ため、spec は `pending` で置き、**上流 15 項の解消待ち**を明記する。紹介日（context/start_time）は **16 項**（EVENT_CONTEXT 未永続化）により含めない。FHIR facade／FSH の jp_referral 出力は **17 項**（FieldExtractor が INSTRUCTION を辿らない）により 8 Errors のまま。したがって 11/5 凍結デモにおける jp_referral の役割は「ドロップ → フォーム生成 → パスカード検索の着地（祖先ルート名込み、`skoba/anlage#{GOAL}`）」までに縮退し、AQL 統一性の実証（本節）は上流解消後（12 月世界公開の準備期）へ送る。凍結受入条件（`spec/demo/` 4 クエリ）は変更しない。

## 9. 可逆性ノート

1 枚テンプレート＋写像 2 本を戦略とするが、JP-CLINS の実インジェスト実装時に写像の捻れが許容を超えた場合、**同じ骨格を共有する JP-CLINS プロファイル版 OPT を分岐してよい**。AQL の包含照合はアーキタイプ基準のため、骨格共有下では分岐してもクエリ層は壊れない（判断時期: 凍結後の実インジェスト着手時）。

## 10. 段階付けと変更履歴

### 段階付け（v2.1、2026-09-25）

| 段階 | 内容 | 状態 |
|---|---|---|
| **v0.1** | 様式11 直写・narrative-first（現物）: 紹介先／紹介元／診療科／担当医／医師（organisation・person 系）、傷病名（DV_TEXT）、既往歴及び家族歴（story）、症状経過及び検査結果・治療経過（clinical_synopsis ×2）、紹介目的（at0062）・サービス名（at0121）・備考 | **Anlage 登録済み**（dev、R4）。fixture 化は `#23` (3) |
| **v0.2** | 現在の処方（medication_order、最小サブセット）＋主訴（EVALUATION.reason_for_encounter）＋アレルギー（adverse_reaction_risk）。傷病名の ICD-11 束縛。患者（other_context）配置の可否 | 人間が AD で組み立て |
| **v0.3 以降** | 既往歴二本立て（story + problem_diagnosis/problem_qualifier）・検査結果構造化（laboratory_test_result）・感染症（infectious_disease_summary）・生活歴（social_summary）。12 月でも可 | — |

v0.2 着手前の裁定事項（v0.1 実測から）——**2026-09-25 に統括が裁定、すべて v0.1 の実装を採用**:

1. **症状経過の ENTRY 型**（§3.1 No.12）: **clinical_synopsis で確定**（様式11 直写を優先。判定則 4 の例外）。
2. **同一アーキタイプ複数出現の判別**（§2）: **name 述語で確定**（AD が at0000 に与えた ja 名を凍結。AQL は `items[openEHR-EHR-CLUSTER.organisation.v1, '紹介先医療機関']`）。
3. **紹介目的の at-code**（§3.1 No.8）: **at0062 改名使用で確定**。

併せて: デモ役割の縮退（§8 補記）と、上流候補 15〜17 項の相互参照（§8 補記）。

### 変更履歴

- v2（2026-09-04）: 人間レビュー完了版を正典化。既定値 2 件（No.17 案a／No.19 不採用）を置く。
- **v2.1 追記 2（2026-09-25、v0.2 再ドロップ）**: §7 に at0077 発症日時・at0073 診断確度と、at0002 の ICD-11 代替制約（v0.2）を追記。v0.2 では clinical_synopsis ×2 の要素名がルート別に「症状経過及び検査結果」「治療経過」へ改名され（§3.1 No.12/14 の裁定と整合）、at0062 の説明に主訴の包含が明文化された（No.9 主訴は v0.2 でも独立エントリ無し＝紹介目的に畳む運用）。改版差分は `docs/reports/referral-intake-log.md` R10。
- **v2.1 補記（2026-09-25、統括裁定）**: §10 の裁定事項 3 件を v0.1 実装で確定、§8 にデモ役割の縮退と上流 15〜17 の相互参照を補記（`docs/design/jp-referral-freeze-batch-plan.md` 項目 4）。
- **v2.1（2026-09-25）**: §7 を jp_referral v0.1 の診断ドロップから転記（`skoba/anlage#23` (2)）。§2 を v0.1 実測骨格（現行 CKM 名・protocol 配置・スロット at-code）へ差し替え、判別の原理を改定。§3.1（実装突合表）・§5 系譜 2 行・§10 段階付けを追加。設計値からの差分 3 件は v0.2 前の裁定事項として保留。
