# jp_referral 手写像 canonical JSON（`skoba/anlage#23` (4)）

`spec/integration/jp_referral_aql_spec.rb` が読む fixture の置き場。契約
`docs/design/referral-v2-inventory.md` §8 の受入検証計画（凍結前は手動写像 1 事例ずつ）。

| ファイル | 種別 | 出所 | 状態 |
|---|---|---|---|
| `mml-case1.canonical.json` | reduced（実 MML 紹介状 1 通からの手写像、作例値に置換） | 統括供給の MML 紹介状（裁定 C） | **未供給** |
| `jpclins-case1.canonical.json` | reduced（JP-CLINS 準拠 Bundle 1 通からの手写像、NoEntry 作例可） | 統括供給の Bundle（裁定 C） | **未供給** |
| `skeleton.canonical.json` | synthetic skeleton（at-code は jp_referral.opt の実物、値は作例、臨床文書ではない。referral-intake-log R6 変種 4 と同形） | `jp_referral_aql_spec` の構造骨格を切り出し（2026-10-20）。`rake demo:reset` のサンプルと共有 | 供給済み |

写像規則: 契約 §6（MML 写像は薄い写像・再配置 2 件のみ変換／JP-CLINS は節単位で
340/370/360/330/430/220）。at-code は `spec/fixtures/opt/jp_referral.opt` の実物のみ
（規律 3）。個人情報は含めない。

RM 側の実体化（15 項）は openehr-rails 0.8.0 で解消。name 述語の AQL（`docs/upstream-candidates.md` 24 項、openehr-ruby#60）が
解消するまで spec は `pending`。
