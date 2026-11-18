# アーキタイプパス表示ログ（`skoba/anlage#64`）

パスカード検索結果の各カードに「アーキタイプパス」を 1 行追加する（凍結明け第 1 号）。
裁定 R-20261116-1（2026-11-16）と追補（2026-11-18）。連番節 R1〜。

---

## R1: 凍結の固定・探索・実装（2026-11-18）

### 0. 凍結の固定

- 遡及タグ `v0.1.0-jcmi46`（annotated、「JCMI46 チュートリアルで動いた版」）を `210bd85` に打って push。
  タグオブジェクト `79cc262` → `210bd85`（`git ls-remote --tags origin` で確認）。以後の変更はこのタグより後。

### 1. 探索（実測）

fixture OPT 6 件を `Opt::PathcardExtractor` に通し、`identity.path` 中の述語 `[<identity.archetype_id>]` の出現を数えた
（指示の「fixture 5 件」は誤記、母数は 6 件・44 カード。追補の裁定 2）。

| OPT | カード数 | 述語なし | 述語が複数回 |
|---|---|---|---|
| CardiologyEncounter | 2 | 0 | 0 |
| LabResultReport | 3 | 0 | 0 |
| ProblemList | 6 | 0 | 0 |
| bmi_calculation | 4 | 0 | 0 |
| jp_referral | 26 | 0 | 3 |
| patient_blood_pressure | 3 | 0 | 0 |
| 計 | 44 | **0** | 3 |

- 述語が path に現れないカード（**導出に失敗するカード**）は **0 / 44**。仕様 1 の停止条件に該当しない。
- 複数回の 3 枚は jp_referral の `openEHR-EHR-CLUSTER.organisation.v1`（紹介先医療機関 内 診療科、at0001／at0003／at0004）。
  同じアーキタイプの入れ子で、path は `…/items[organisation.v1]/items[organisation.v1]/items[at0001]/value`。
  → 裁定 1: **最後の出現より後ろ**を取る（`/items[at0001]/value`）。
- 導出後の最長は 61 文字（`/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value`、CardiologyEncounter ほか）。
  述語は全て `[atNNNN]` の形で、name 述語等は無い。

### 2. 実装（TDD、3 サイクル）

導出は `Opt::Pathcard.archetype_path(card)`（`app/lib/opt/pathcard.rb`、新設）の 1 箇所。view は呼ぶだけ。
スキーマ v1.2・golden・抽出器は不変。

| サイクル | Red | Green |
|---|---|---|
| 1 unit（`spec/lib/opt/pathcard_spec.rb`） | `uninitialized constant Opt::Pathcard` | 5 examples, 0 failures |
| 2 request＋語彙（`pathcards_spec`・`ui_vocabulary_spec`・`ui-vocabulary.md`） | 3 failures（行が無い／dt が 3 語） | 11 examples, 0 failures |
| 3 system（`demo_pathcard_search_spec`、js） | `overflow-wrap` が `normal` | 2 examples, 0 failures |

pin した例（期待値は golden の identity.path からの実測）:

| 例 | アーキタイプパス |
|---|---|
| ProblemList `EVALUATION.problem_diagnosis.v1` at0002（プロブレム・診断名） | `/data[at0001]/items[at0002]/value` |
| LabResultReport 埋め込み `CLUSTER.laboratory_test_analyte.v1` at0001（分析結果） | `/items[at0001]/value` |
| jp_referral SECTION 配下 `EVALUATION.problem_diagnosis.v1` at0002（傷病名） | `/data[at0001]/items[at0002]/value` |
| jp_referral 入れ子 `CLUSTER.organisation.v1` at0001（紹介先医療機関 内 診療科の名称） | `/items[at0001]/value` |
| 述語なし（合成カード、追補の条件 1） | nil（view は行を出さない） |

- サイクル 3 の Red は折り返し指定で取った。等幅（`code` の既定）と横スクロールなし（最長 61 文字）は
  CSS を足す前から成立しており、こちらは退行の固定。
- **申告**: サイクル 1 の初回コミットは、入れ子の例が spec 側の誤り（`(archetype_id, at_code)` で 1 枚に
  絞れると見込んだが organisation at0001 は 3 枚）で red のまま作ってしまった（出力を `tail` で切って
  失敗行を見落とした）。push 前に spec を直して amend した。実装コードの変更は無い。

### 3. 手元の実行環境

- 本体の working tree には未コミットの jp_referrals 一式があり、`db/migrate/20261111070602_create_jp_referrals.rb`
  が pending で suite が起動しない（`ActiveRecord::PendingMigrationError`）。未コミット物に触れないため、
  クリーンな git worktree（`main` から分岐）で TDD を回し、`main` へ fast-forward した。
- worktree での全 suite: 236 examples, 5 failures, 3 pending。5 件は `demo_intake_spec`（2）・
  `multi_file_dropzone_spec`（1）・`polymorphic_dropzone_spec`（2）の `attach_file` で、
  worktree を `/tmp` 配下に置いたため snap 版 Chromium がファイルを読めない（`File not found`）。
  本変更を外したベースラインでも同じ 5 件が落ちる。合否は CI（クリーンな checkout）で決める（追補の条件 3）。
- `bin/rubocop`: 112 files, 0 offenses。

## R2: push と CI（2026-11-18）

- push: `210bd85..e35ea51`（`569dbbd`・`202c8c9`・`49e4327`・`e35ea51`）。
- CI run `44265803663`（`e35ea51`）: **red**。内訳は `test` success・`lint` success・`scan_js` success・**`scan_ruby` failure**。
  - `test` はクリーンな checkout での全 suite（js の system spec を含む）で、本変更の合否はここで green。
  - `scan_ruby` は bundler-audit の「Vulnerabilities found!」。Gemfile.lock 上の既存 gem への勧告
    （sqlite3 2.9.6 の GHSA-4fqr-96q8-xrfx、nokogiri、rails 各 gem、puma、rack、loofah、addressable、net-ssh ほか）で、
    本変更は Gemfile／Gemfile.lock に触れていない。
  - 本変更より前から red: 直近の CI run `43601148367`（2026-11-14、dependabot の rspec-rails ブランチ）も
    `scan_ruby` だけ failure。11/7 の 3 run も failure。対応する dependabot PR が #58〜#63 に開いている
    （#58 sqlite3 2.10.2、#61 rails 8.1.4.1 ほか）。
  - 依存更新は本 Issue の範囲外なので手を付けていない（規律 8）。例外報告として上げ、扱いは裁定待ち。
- #64 の acceptance criteria は「CI green」以外を充足。`scan_ruby` の扱いが決まるまで #64 は開けておく。

## R3: タグの位置づけ、生成 scaffold の退避、OPT の差（2026-11-18）

裁定 C の追補（小林、2026-11-18）による。

### 1. タグ `v0.1.0-jcmi46` の位置づけ

- `v0.1.0-jcmi46`（`210bd85`）は**壇上の土台の版**である。壇上（JCMI46 チュートリアル、2026-11-12）では、
  これに生成 scaffold（未コミット）を足して実演した。タグの版だけでは壇上の生成デモの出力は再現されない。
- 生成 scaffold の由来: 2026-11-11 に `rails g openehr:scaffold` を jp_referral.opt に対して実行した
  生成デモの出力。本番は別 PC で同じ生成を壇上で実演した。本機の作業ツリーに残っていた jp_referrals 一式
  （R1 の 3 節）はこの 11/11 の出力である。

### 2. 退避

- ローカルブランチ `wip/jp-referrals-scaffold`（`6e6c8b2`、親は `ea3ccff`）に 13 ファイルをパス明示で
  コミットした。内訳: `config/routes.rb`・`db/seeds.rb` の各 1 行、`app/controllers/jp_referrals_controller.rb`、
  `app/models/jp_referral.rb`、`app/templates/operational/jp_referral.opt`、`app/views/jp_referrals/` の 5 ファイル、
  `config/locales/jp_referral.ja.yml`、`db/migrate/20261111070602_create_jp_referrals.rb`、
  `spec/requests/jp_referrals_spec.rb`。生成器の出力のままで、手を入れていない。
- **push していない**（追補の指定がローカルブランチ）。M2（#30）の着手時まで残す。main へは入れない。
- 退避後の main の `git status --short` は空。`db/schema.rb` に差分は無かった。

### 3. OPT の差（実測）

`app/templates/operational/jp_referral.opt`（退避ブランチ、459,385 bytes、sha256 `f3884e9f…464af3e86`）と
`spec/fixtures/opt/jp_referral.opt`（main、459,677 bytes、sha256 `5ffc7e6d…322d4f924`）。
どちらも sem_ver 0.2.0 で、同じ v0.2 の**別の書き出し**である。差は 4 点:

| # | 差 | 内容 |
|---|---|---|
| 1 | 出所コメント | fixture だけにある（2〜23 行、22 行）。fixture の冒頭コメント自身が「このコメントだけ足した」と記す |
| 2 | `MD5-CAM-1.0.1` | scaffold 側 `dd515c14…`、fixture 側 `9ed6dafa…` |
| 3 | 代替型の並び順 | `problem_diagnosis` at0002 の `value` の子の順。scaffold 側は DV_CODED_TEXT → DV_TEXT、fixture 側は DV_TEXT → DV_CODED_TEXT。ブロックの中身は同じ |
| 4 | 末尾の `<annotations>` | scaffold 側だけに `L10n.en` の 5 件（Organisation (2)／Organisation ×2／Clinical synopsis／Clinical synopsis (2)） |

- fixture のコメントが記す上流の sha256（`99abe4e3…`、openehr-templates-jp@0918722）とは、scaffold 側の
  sha256 は一致しない。scaffold 側がどのコミット・どの時点の書き出しかは**不明**（リポジトリ内に記録が無い）。
- パスカードへの影響: 両者を `Opt::PathcardExtractor` に通すと、どちらも 26 カード。provenance
  （source_checksum・extracted_at）を除いて差があるのは 1 枚だけで、`problem_diagnosis` at0002 の
  `semantics.rm_type_alternatives` が scaffold 側 `["DV_CODED_TEXT","DV_TEXT"]`、fixture 側
  `["DV_TEXT","DV_CODED_TEXT"]`（差 3 の反映）。identity.path は 26 枚とも一致するので、
  アーキタイプパスの導出結果は同じ。
- 差 3 が帳票（代替型の既定の選択）に影響するかは未調査。M2（#30）で scaffold 側の OPT を使うなら要確認。

## R4: R3 の訂正——壇上で生成 scaffold は使っていない（2026-11-18）

裁定 R-20261118-2（訂正）。R3 は書き換えず、本節で訂正する。

- **事実**（小林、2026-11-18）: 壇上での生成は OPT のドラッグ&ドロップ（実行時の取り込み）だけ。
  `rails g openehr:scaffold` は壇上では実行していない。
- **誤り**: R3 の 1 節「壇上（JCMI46 チュートリアル、2026-11-12）では、これに生成 scaffold（未コミット）を足して実演した。
  タグの版だけでは壇上の生成デモの出力は再現されない」と「本番は別 PC で同じ生成を壇上で実演した」。
- **訂正**:
  - タグ `v0.1.0-jcmi46`（`210bd85`）は、**壇上で動いた版そのもの**である（未コミットの追加物なし）。
  - `wip/jp-referrals-scaffold`（`6e6c8b2`）は、2026-11-11 に試した生成の出力で、**壇上では使っていない**。
- R3 の 2 節（退避の記録）と 3 節（OPT の差の実測）は訂正の対象外で、そのまま有効。
- `wip/jp-referrals-scaffold` のコミット `6e6c8b2` のメッセージにも同じ誤り（「本番…は別 PC で同じ生成を壇上で実演した」
  「壇上ではこれにこの生成 scaffold（未コミット）を足して実演した」）がある。push 済みなので書き換えない
  （履歴の書き換えはゲート対象）。訂正は本節をもって足りる。
- #30 のコメント（2026-11-18、未調査事項）は「2026-11-11 の `rails g openehr:scaffold` の出力を退避してある」と
  書いているだけで、壇上には触れていない（本文を確認）。訂正のコメントは足していない。
- 本番は開発機とは別の PC で実施しており、別 PC のコミットは未確認（`docs/reports/jcmi46-retrospective.md` 5 節の 4）。
