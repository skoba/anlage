# 診療情報提供書テンプレート v2（jp_referral）— 骨格契約

- 版: v2（2026-09-04）。出典: `referral-v2-inventory-v2.xlsx`（三面表・人間レビュー完了: OK 17 / 修正 9 / 不要 3 / 未記入 0）
- 状態: **正典（スタートポイント）**。AD 実測待ち項目（§7）が埋まると v2.1 とする
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

## 2. 節骨格（様式11 の欄が節として現れる）

```
COMPOSITION.referral
├─ SECTION.referral_details
│   ├─ INSTRUCTION.request-referral
│   │    紹介目的: description[at0009]/items[at0064](記述・主)+ items[at0062](コード化理由 0..1・束縛サイト候補)
│   │    依頼内容: Service requested 要素【暫定・at-code 実測待ち】
│   │    protocol/receiver SLOT : CLUSTER.organisation (1..1) + CLUSTER.individual_professional (0..1)   ← 紹介先
│   │    protocol/requester SLOT: CLUSTER.organisation + CLUSTER.individual_professional                 ← 紹介元
│   └─ Details SLOT: OBSERVATION.story（症状経過）・EVALUATION.clinical_synopsis（治療経過）・
│        OBSERVATION.laboratory_test_result（検査結果・感染症検体検査を含む）
├─ SECTION[傷病名・主訴](adhoc): EVALUATION.problem_diagnosis（傷病名）・EVALUATION.reason_for_encounter（主訴）
├─ SECTION[既往歴・家族歴](adhoc): OBSERVATION.story（既往歴 narrative）・EVALUATION.problem_diagnosis + CLUSTER.problem_qualifier（過去の病名）・
│        EVALUATION.family_history・EVALUATION.adverse_reaction_risk・EVALUATION.infectious_disease_summary・EVALUATION.social_summary
├─ SECTION.medication_order_list ⊃ INSTRUCTION.medication_order（現在の処方）
├─ SECTION[備考](adhoc): free_text
└─ context: start_time（紹介日）／other_context/patient SLOT: CLUSTER.individual_personal（患者。交換文書として文書内に自己完結）
```

判別の原理: 同一アーキタイプの複数出現（story×2、problem_diagnosis×2、organisation×2）は **節配置と SLOT 役割**で構造的に区別する。名前制約（node name）に依存しない → 抽出器の name 制約対応は不要。

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

## 6. 写像方針

- **様式11 射影**: 節＝欄で 1:1。主訴は症状経過欄へ、生活歴・アレルギー・感染症は既往歴及び家族歴欄または備考へ（射影規則で確定）。
- **JP-CLINS 写像**（別表・IG v1.13.0）: 節単位で 340/370/360/330/430/220 と対応。referral_details は 950/360/330/検査結果へ扇状展開。SECTION[既往歴・家族歴] からは **アーキタイプ種別をキー**に 370／家族歴／AllergyIntolerance／Observation_Common へ展開。ENTRY 型非対称の注記: FHIR は主訴を Condition、社会歴を Observation で表す。
- **MML 写像**: mml_referral の構造がほぼそのまま（薄い写像）。再配置 2 件のみ要変換。
- **インジェスト二水準**: JP-CLINS「NoEntry」作例に倣い、narrative 水準（section.text → story / at0064 等）と構造化エントリ水準（entries → 各アーキタイプ）の両方を受ける。

## 7. AD 実測待ち（契約の正典値の空欄）

- SLOT の実 at-code: protocol/receiver・protocol/requester・referral_details Details・other_context/patient
- 要素の実 at-code: Service requested（No.20）
- 新規 6 アーキタイプの ID・版（v0/v1）・公開状態・ja 訳の有無
- individual_personal の職業要素の有無（No.5）／organisation の部門表現（要素 or occurrence 2）（No.1）
- 記入方法: jp_referral 初版 OPT を Anlage に診断ドロップし、抽出されたパスカードの path から転記する（手写しは不要）

## 8. 受入検証計画（Step 4・凍結前は手動写像 1 事例ずつ）

- MML 側: 実 MML 紹介状 1 通 → Composition（手動写像）→ 同一 AQL で引けること
- JP-CLINS 側: 準拠 Bundle 1 通（NoEntry 作例可）→ 同上
- 統合 spec: 「両源から同じ AQL で引ける」を jp_referral の受入条件とする。変換器の自動化（fhirbridge / MML パーサ）は 12 月以降

## 9. 可逆性ノート

1 枚テンプレート＋写像 2 本を戦略とするが、JP-CLINS の実インジェスト実装時に写像の捻れが許容を超えた場合、**同じ骨格を共有する JP-CLINS プロファイル版 OPT を分岐してよい**。AQL の包含照合はアーキタイプ基準のため、骨格共有下では分岐してもクエリ層は壊れない（判断時期: 凍結後の実インジェスト着手時）。

## 10. 変更履歴

- v2（2026-09-04）: 人間レビュー完了版を正典化。既定値 2 件（No.17 案a／No.19 不採用）を置く。
