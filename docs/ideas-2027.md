# ideas-2027（スコープ外アイデアの退避先）

`CLAUDE.md` 絶対規律 8: 指示外の新機能・改善案は実装せずここに記録して先へ進む。本ファイルは 2026-09-25 に初出（それまで参照のみで実体が無かった）。

## ルート名（C_ARCHETYPE_ROOT の at0000 term／name 制約）をパスカードの semantics に載せる（2026-09-25、`#23` R6 より）

- 発端: jp_referral v0.1 で「既往歴」「傷病名」「治療経過」「紹介先」が `Opt::PathcardSearch` に着地しない。様式11 の欄名は AD がルートの at0000 に与えた ja 名（既往歴及び家族歴／傷病名／治療経過／紹介先医療機関）で、ELEMENT カードには現れない（`docs/reports/referral-intake-log.md` R4 2 節・R6 1 節。R1 §4 の mml_referral「Past history」name 固定値と同じ構造）
- 案: ELEMENT カードの `semantics` に祖先ルートの名前列（`root_names: ["紹介状の詳細情報", "紹介先医療機関", "診療科"]`）を持たせる／またはルート自体を「文脈カード」として 1 枚起こす。`component_terminologies` は archetype_id で束ねるため、同一アーキタイプ複数ルートの at0000 は OPT XML の各 C_ARCHETYPE_ROOT 直下 term_definitions から読む必要がある（`#29` の path 修正と同じ walk で拾える）
- スコープ規律 8 により未実装。出題化もしない（R6 は観察のみ）

## GDL2 評価器（12 月）— `config/form_behaviors.yml` の差し替え点（2026-10-12、`#47` 裁定 A）

- Phase 3 の BMI 自動計算は `config/form_behaviors.yml`（template_id → target／inputs／formula／cases／round／on／editable）で宣言し、式は GDL2 互換の安全サブセット（四則・累乗・round・比較）を `Opt::Formula` で評価する。判定の `cases`（when／else → 文言）は **GDL2 の rule/when と同型**で、GDL 評価器を入れる時はこの yml を GDL2 ガイドラインへ差し替える（`docs/design/demo-integration-plan.md` 4 節）
- スコープ規律 8 により評価器本体は実装しない
