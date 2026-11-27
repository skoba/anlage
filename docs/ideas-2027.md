# ideas-2027（スコープ外アイデアの退避先）

`CLAUDE.md` 絶対規律 8: 指示外の新機能・改善案は実装せずここに記録して先へ進む。本ファイルは 2026-09-25 に初出（それまで参照のみで実体が無かった）。

## ルート名（C_ARCHETYPE_ROOT の at0000 term／name 制約）をパスカードの semantics に載せる（2026-09-25、`#23` R6 より）

- 発端: jp_referral v0.1 で「既往歴」「傷病名」「治療経過」「紹介先」が `Opt::PathcardSearch` に着地しない。様式11 の欄名は AD がルートの at0000 に与えた ja 名（既往歴及び家族歴／傷病名／治療経過／紹介先医療機関）で、ELEMENT カードには現れない（`docs/reports/referral-intake-log.md` R4 2 節・R6 1 節。R1 §4 の mml_referral「Past history」name 固定値と同じ構造）
- 案: ELEMENT カードの `semantics` に祖先ルートの名前列（`root_names: ["紹介状の詳細情報", "紹介先医療機関", "診療科"]`）を持たせる／またはルート自体を「文脈カード」として 1 枚起こす。`component_terminologies` は archetype_id で束ねるため、同一アーキタイプ複数ルートの at0000 は OPT XML の各 C_ARCHETYPE_ROOT 直下 term_definitions から読む必要がある（`#29` の path 修正と同じ walk で拾える）
- スコープ規律 8 により未実装。出題化もしない（R6 は観察のみ）

## 帳票のロジック — いまは YAML の軽い定義を優先し、GDL2 が普及した時点で乗り換える（2026-11-27、R-20261127-16。もとは 2026-10-12 `#47` 裁定 A の「GDL2 評価器（12 月）」）

- BMI 自動計算などの帳票の振る舞いは `config/form_behaviors.yml`（template_id → target／inputs／formula／cases／round／on／editable）で宣言し、式は安全サブセット（四則・累乗・round・比較）を `Opt::Formula` で評価する（`docs/design/demo-integration-plan.md` 4 節）
- 以前は「GDL 評価器を入れる時に、この yml を GDL2 ガイドラインへ差し替える」としていた。いまは YAML の軽い定義を優先し、テンプレートと一緒に実行時に登録できる形に育てる（`docs/design/u1-patient-chart-plan.md` 4 節。U3）。GDL2 は openEHR の仕様として正式に採用されている（CDS の状態は STABLE）。いま採らない理由は、仕様の状態ではなく普及の見込み（主な実装が採用している様子が無い）（小林、11/27）
- 乗り換えの条件: 主な実装が GDL2 を採用し、定義を持ち運ぶ相手ができたとき。乗り換えのとき変換を書けるように、軽い定義と GDL2 の概念の対応を、定義の層の計画書に書く
- 業務の流れ（Task Planning に当たるもの）も同じ: いまは YAML の軽い定義。Task Planning は定着しておらず、公式の状態も最新のリリースで RETIRED、開発版で PAUSED（R-20261127-16）

## 数量の表示を、画面全体で精度を作らない形にそろえる（2026-11-27、skoba/anlage#250 の範囲の外）

- 患者の画面は `Opt::QuantityDisplay` で、整数の値に小数点を付けない（148.0 → 148）。記録の画面の「記録の中身」（#191）と、
  クエリビルダー・AQL 照会の結果は、いまも `134.0` と出る（`spec/system/patient_chart_spec.rb`、`spec/system/demo_query_builder_spec.rb` が pin している）
- そろえるなら、同じ部品を使い、spec と受け入れの台本（H1・H2・J5・F1）を追随させる。AQL の結果は gem が返す数をそのまま出しているので、出し方の決まりが要る
