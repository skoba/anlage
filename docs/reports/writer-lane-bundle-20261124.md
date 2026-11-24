# バンドル報告: anlage（書く側）2026-11-24

裁定 ID: R-20261124-10（作業列）、R-20261124-8（進め方）、R-20261124-4・R-20261124-5（計画の承認）。
本フェーズのログ: `docs/reports/m2-log.md`（R1〜R7。R7 は PR #105 の中）と `docs/reports/m3-log.md`（R1〜R4）。

## 自己承認した判断（一覧。根拠と捨てた案は各ログの節）

| # | 判断 | ログ |
|---|---|---|
| 1 | ルートの archetype_id は登録時に `web_template` に入れ、古い登録では OPT から引く（移行なし） | m2 R1 |
| 2 | Composition の JSON の取り込みの照合を `archetype_details.template_id` に改めた（計画書の一覧に無い箇所） | m2 R1 |
| 3 | B の fixture は jp_referral.opt（実物）を使い、値を入れる entry を選んで衝突を避けた。POST の通しは未実施 | m2 R2 |
| 4 | 保存可否に「未対応クラスの entry」「衝突する field 名」を足した（判定規則は builder に置く） | m2 R2 |
| 5 | reader と committer も SECTION を辿るようにした（計画書の一覧に無い箇所） | m2 R2 |
| 6 | 設計書で見つけた欠陥（terminology_id、category）を、設計書 5 節の順に直した | m2 R3・R4・R6 |
| 7 | `Gemfile.lock` は openehr の 2 行だけを書き換えた（`bundle update` が無関係な 11 行を消したため） | m2 R5 |
| 8 | デモ Q2 も本来形に置き換え、実ブラウザの spec のクエリもそろえた | m2 R5 |
| 9 | `Opt::TemplateTerms` を `Opt::RootTerms` に置き換えた（6 つの fixture で出力の一致を実測） | m2 R7 |
| 10 | W1 と W2、W3 と W4 を、それぞれ 1 つの Issue・1 つの PR にまとめた | m3 R1・R2 |
| 11 | engine の画面は、engine の layout を anlage の側で上書きして同じナビに入れた（gem は変えない） | m3 R1 |
| 12 | カルテ記録の画面の「FHIR プロファイル」を「テンプレートの詳細」に置き換えた（計画書の問い 2 の案） | m3 R4 |
| 13 | 設計書（narrative のゲートを含む）と M3 の計画書を、docs のみの PR としてセッションがマージした | m2 R3 |

## 作業列の状態

| 作業列 | 内容 | 状態 | PR → main | CI run（PR の head） |
|---|---|---|---|---|
| 1 | 計画書 2 枚を承認済みに、`CLAUDE.md` に「全開の進め方」 | 済み | #78 → `6c100e0` | 45389103716 green |
| 2 | A（`#54`）ルートの archetype_details | 済み | #79 → `6dac631` | 45389869030 green |
| 2 | B（`#80`）SECTION 配下の ENTRY | 済み | #83 → `c09d72f` | 45391599848 green |
| 3 | openehr 2.5.0 への版上げ（`#90`） | 済み（人間がマージ） | #92 → `94561e9` | 45394526663 green |
| 3 の続き | `Opt::TemplateTerms` の撤去（`#104`） | **人間のマージ待ち**（ファイルの削除を含む） | #105（head `6947982`） | 45398303112 green |
| 4 | RM 属性の設計書 | 済み。**narrative はゲート** | #85 → `62bc45c` | 45392182820 green |
| 4 の続き | terminology_id（`#86`） | 済み | #88 → `91715f0` | 45392707470 green |
| 4 の続き | category（`#87`） | 済み | #93 → `b0cdc96` | 45394104994 green |
| 5 | M3 の計画書 | 済み | #94 → `7d466ad` | 45394296744 green |
| 5 | W1・W2 統合レイアウト（`#95`） | 済み | #97 → `0d14285` | 45395368272 green |
| 5 | W3・W4 テンプレートの詳細と版の履歴（`#98`） | 済み | #99 → `2d9c5f5` | 45395959612 green |
| 5 | W5 版の差分（`#100`） | 済み | #101 → `4633cae` | 45396875862 green |
| 5 | W6 FHIR プロファイルのリンク（`#102`） | 済み | #103 → `e3c168e` | 45397579724 green |
| — | `#82` reader の coded_free | 済み（coded_manual は未確認で、Issue は開けたまま） | #106 → `4a0f505` | 45398599898 green |
| 6 | F・D・C・E・I | **openehr-rails 0.9.0 の公開待ち**（RubyGems は 0.8.0） | — | — |
| 7 | M3 の残り（患者と EHR、カルテ記録） | 6 のあと | — | — |

main の CI: `e3c168e` までは run 45397804936 green。`4a0f505`（#106 のマージ）は run 45398804000 が、この報告を書いた時点で実行中。

## `#82` の Red（進行ログに書けなかった分）

PR #105 が `docs/reports/m2-log.md` の末尾を触っていて競合するので、ここに書く。

```
Opt::CompositionReader#82 coded_free の読み戻し 自由記述で保存した傷病名（DV_TEXT）を読み戻し、選択肢の診断確度はコードで読み戻す
  expected: {"problem_diagnosis_at0002" => "高血圧症", "problem_diagnosis_at0073" => "at0074"}
       got: {"problem_diagnosis_at0002" => nil, "problem_diagnosis_at0073" => "at0074"}
```

Green: 開発機の全 suite 286 例 0 失敗、2 pending。

## 開いているゲート（人間・統括の判断を待つもの）

1. **INSTRUCTION の narrative の作り方**（`docs/design/rm-attributes-without-inputs.md` 6 節）。候補 4 つ、推奨は B（複数項目からの組み立て）。
   D（INSTRUCTION を組む作業）は、この答えと 0.9.0 の両方を待つ
2. **PR #105 のマージ**（ファイルの削除を含むので人間）
3. M2 の計画の保留分（R-20261124-5 問い 4 の縮退の案、人間の入力 4 点: 手写像の元 2 通、jp_referral v0.3 の OPT ほか）

## 人間への依頼

- SECTION を持ち、未対応クラスの entry も複数ルートの衝突も無い OPT を 1 つ（B の POST の通しの spec 用。m2 R2）
- coded_manual の項目（コード化が必須で、選択肢を持たない DV_CODED_TEXT）を持つ OPT（`#82` の残り）
- M3 の計画書 4 節の問い 3 点（左ナビの項目、FHIR プロファイルのリンクの置き場所、FSH を画面に出すか）。案のとおり進めた。違えば直す

## 進め方について気づいたこと

- **進行ログの末尾への追記が、PR どうしで競合する**。変更履歴を断片にしたのと同じ問題が、`docs/reports/<phase>-log.md` に残っている。
  今日は、main を取り込むマージで 2 回解消した（#88、#92）。人間のマージ待ちの PR があるあいだは、あとの PR がログを触れない。
  ログも PR ごとの断片（たとえば `docs/reports/m2-log.d/`）にするかどうかは、統括の判断
- **PR のブランチへの force-push は、実行環境が拒否した**（rebase のあとの push）。回避せず、main を取り込むマージに切り替えた
- **台帳は、自分宛ての 1 行（R-20261124-10）だけを書いた**。R-20261124-4 と R-20261124-5 の行も anlage 宛てだが、
  3 行まとめての書き込みを実行環境が拒否したので、触っていない。どちらも「発行」のまま
- 開発機には日本語のフォントが無く、headless Chrome のスクリーンショットでは日本語が豆腐になる（m3 R1）

## 次に進めるもの

- 0.9.0 が公開されたら F（受け入れと迂回の撤去）。engine の layout が変わっていないかを、F の確認項目に足す
- 設計書 5 節の 3（ノードの名前をテンプレートの用語から取る）。`Opt::RootTerms`（PR #105）を使うので、#105 のマージのあと
- 設計書 5 節の 4（自動で入る値を帳票に見せる）は、3 のあと
