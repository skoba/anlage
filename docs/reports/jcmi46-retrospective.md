# JCMI46 チュートリアル本番の振り返り（2026-11-12）

裁定 R-20261117-4（1 節）。入力は本番についての小林の口述（2026-11-18 受領）。
口述に無いことは書いていない。リポジトリの実測で補った箇所は「実測」と明記した。

- 本番は開発機（WSL）とは別の PC で実施した。別 PC のコミットは未確認
- 進行は手順どおり。質疑はほとんど無く、時間は少し余った
- 行き先の記号: M2・M3・S1〜S4・見送り。本文書の作成時点で、リポジトリ内に M3・S1〜S4 の定義が無い
  （M2 は裁定 R-20261118-2 で #30 と対応づけられている）。対応づけられない行は「未定」とした（末尾の質問 1）

## 1. 摩擦

| 画面 | 操作 | 起きたこと | 期待したこと | 重さ | 行き先 |
|---|---|---|---|---|---|
| 帳票（jp_referral） | 入力して保存 | EVALUATION アーキタイプが保存できないため、帳票は扱えないと口頭で断った | 帳票から保存できる | 中 | M2（#30） |

### 該当する Issue と原因の層（実測、main `f3a4dc8`）

- 該当 Issue は **`skoba/anlage#30`**（`Opt::CompositionBuilder` が INSTRUCTION／SECTION 配下 ENTRY を扱えない）。
- `spec/fixtures/opt/jp_referral.opt`（v0.2）を登録すると、帳票は閲覧専用になる:
  `web_template["form_capability"]` = `preview_only`、理由 = **`unexpected wrapper depth for EVALUATION`**。
  画面には「保存は未対応（#30）: unexpected wrapper depth for EVALUATION。このフォームは閲覧専用です。」と出て、
  保存ボタンは出ない（`app/views/forms/show.html.erb:5`、`spec/system/demo_pathcard_search_spec.rb`）。
  口述の「EVALUATION アーキタイプが保存できない」は、この理由の文言と一致する。
- 原因は EVALUATION そのものではなく、**SECTION 配下に置かれた ENTRY** である。
  理由の出どころは `app/lib/opt/composition_builder.rb:102`（EVALUATION の外側に包みが残っていると `UnsupportedShape`）。
  jp_referral の ENTRY は 5 件とも `SECTION.referral_details.v0` の配下にある
  （INSTRUCTION 1・EVALUATION 3・OBSERVATION 1）。content 直下に EVALUATION を置く ProblemList は
  `saveable` で、同じ `problem_diagnosis` を保存できる。
- 原因の層: **Anlage**（`Opt::CompositionBuilder`、#30）。#30 の本文は、保存後の RM グラフ側にも未対応があると
  記している（openehr-rails、`docs/upstream-candidates.md` 15・16 項）。そちらが本番時点でどうだったかは今回測っていない。
- 限界: 上の実測は fixture の jp_referral（v0.2）に対するもの。壇上で使った 2 つの OPT
  （あらかじめ作った jp_referral と、その場で作ったデモ用の版）が fixture と同じ内容かは未確認（質問 2）。

## 2. 通過した経路（M2・M3 の回帰対象）

口述の「壇上の流れ」の順。「既存 spec」は、同じ操作を固定している spec を main `f3a4dc8` で探した結果（実測）であり、
壇上の操作と同一であることまでは確かめていない。

| # | 画面 | 操作 | 結果 | 既存 spec（実測） | 行き先 |
|---|---|---|---|---|---|
| 1 | Archetype Designer | デモ用の JP Referral テンプレートをその場で作った | 作れた | 無し（anlage の外） | 未定 |
| 2 | Archetype Designer | あらかじめ作っておいた jp_referral で、OPT のダウンロード操作を見せた | 見せられた | 無し（anlage の外） | 未定 |
| 3 | Archetype Designer | デモ用に作った版の OPT もダウンロードした | ダウンロードできた | 無し（anlage の外） | 未定 |
| 4 | テンプレートの取り込み | 2 つの OPT を anlage にドラッグ&ドロップした | どちらも生成され、帳票になっていることを確認した | `spec/system/demo_intake_spec.rb`（jp_referral.opt の取り込み）、`spec/system/multi_file_dropzone_spec.rb`（複数ファイル） | M2 |
| 5 | 帳票（BMI） | BMI の入力を行った | BMI が自動で計算され、肥満度の判定が出た | `spec/system/demo_bmi_spec.rb` | 未定 |
| 6 | パスカード検索 | 検索を行った | 検索できた | `spec/system/demo_pathcard_search_spec.rb` | 未定 |
| 7 | AQL 照会 | AQL での検索を行った | 成功した | `spec/demo/aql_queries_spec.rb`（件数。照会画面そのものを操作する system spec は無い） | 未定 |
| 8 | コマンドライン | FSH を生成し、できた FSH ファイルを見せた（流れの中での順番は未確認） | 生成でき、見せられた | `spec/tasks/fsh_spec.rb`（`rake fsh:export`。壇上のコマンドがこれかは未確認、質問 3） | 未定 |

- 4 を M2 としたのは、M2（#30）が jp_referral の帳票の保存経路を変えるため。取り込みと帳票の表示が M2 の前後で
  変わらないことが回帰の対象になる。
- 壇上での生成は OPT のドラッグ&ドロップ（実行時の取り込み）だけである。`rails g openehr:scaffold` は
  壇上では実行していない。

## 3. 壇上で約束したこと

| 約束 | 行き先 |
|---|---|
| 12 月公開 | 未定 |
| good first issue を用意する | 未定 |
| 帳票の持ち込みは引き受ける | 未定 |

## 4. 質疑・時間配分

- 質疑: ほとんどなかった
- 時間配分: 少し時間が余った

## 5. 質問（不明な点。推測で埋めていない）

1. M3・S1〜S4 の定義。本文書で「未定」とした行（通過した経路の 1〜3・5〜8、約束の 3 件）の行き先。
2. 壇上で使った 2 つの OPT は、`spec/fixtures/opt/jp_referral.opt`（v0.2）と同じ内容か。
   その場で作ったデモ用の版の帳票は保存できる形だったか（摩擦は 2 つのうちどちらの帳票で起きたか）。
3. 壇上で FSH の生成に使ったコマンド（`rake fsh:export` か）と、流れの中での順番。
4. 別 PC で動かした版（コミット）。タグ `v0.1.0-jcmi46`（`210bd85`）と同じか。
5. 「帳票の持ち込みは引き受ける」の受け口（Issue・連絡先など）は口述に無い。
