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
