# M2（書き込みの完成）の計画

裁定 ID: R-20261124-3（2 節）。状態: **案**。承認までは実装しない。期間の案は 12/1〜12/12（公開 v0.2.0 は 12/20）。

- 基準点: anlage main `86720a5`（openehr 2.4.3、openehr-rails 0.8.0）
- 出口: 紹介状（jp_referral）を帳票から入力して保存し、「紹介先医療機関」で引ける
- 上流の項番は `docs/upstream-candidates.md` のもの。openehr-rails 0.9.0 の計画書は
  openehr-rails のツリー（`c8a6841`）にまだ無いので、0.9.0 に何が入るかは**未確認**

## 1. いまの状態（実測、`spec/fixtures/opt/jp_referral.opt` v0.2）

- 帳票は閲覧専用。理由は `unexpected wrapper depth for EVALUATION`（`app/lib/opt/composition_builder.rb:102`）
- `web_template` は 5 entry・6 field。パスカードは 26 枚で、うち 20 枚は INSTRUCTION（service_request）配下
  （entry は 0 field。上流候補 17 項）。帳票に出ているのは 26 枚中 6 枚ぶん
- field 名の衝突が 1 組: `clinical_synopsis` が 2 つ（同じアーキタイプの 2 つのルート。path も同じ）
- フォーム経路の Composition は、ルートの `archetype_node_id` に template_id が入り、
  `archetype_details` が無い（`composition_builder.rb:35-36`、`skoba/anlage#54`）
- 全要素が空の entry は組まない（`composition_builder.rb:43`）。0 field の INSTRUCTION は今も素通しになる

## 2. 項目（1 Issue = 1 PR）

| # | 項目 | Issue | 0.9.0 を待つか | Red から始める spec の見出し | 触るファイル |
|---|---|---|---|---|---|
| A | ルートの `archetype_node_id` と `archetype_details` | `#54` | **待たない** | 「フォーム保存した Composition のルートが COMPOSITION アーキタイプの ID と archetype_details（archetype_id・template_id・rm_version）を持つ」「RM グラフの template_id 列に template_id が入る」 | `app/lib/opt/composition_builder.rb`、`app/models/template.rb`（ルートの archetype_id を `web_template` に持たせる場合）、`spec/lib/opt/composition_builder_spec.rb`、`spec/requests/compositions_spec.rb` |
| B | SECTION 配下の ENTRY を組む | `#30` から分ける（新規） | **待たない**（SECTION の実体化は 0.8.0 で解消済み、15 項） | 「SECTION 配下の EVALUATION と OBSERVATION を、SECTION の items に入れて組む」「content 直下の ENTRY は従来どおり」（regression pin） | `composition_builder.rb`（`wrapper_chain`、`build`）、`spec/lib/opt/composition_builder_spec.rb` |
| C | 同じアーキタイプの複数ルートを区別する（field 名の衝突） | `#30` から分ける（新規） | **待つ**（22 項が field 名の付け方を変える。先にやると二度手間） | 「clinical_synopsis ×2 の field 名が別々になり、それぞれのルートの名前でラベルされる」「2 つに別の値を入れて保存すると、2 つの EVALUATION に分かれて入る」 | `app/models/template.rb`、`composition_builder.rb`、`app/lib/opt/form_validator.rb`、`app/views/forms/show.html.erb`、対応する spec |
| D | INSTRUCTION（activities／protocol）と多段 CLUSTER を組む | `#30`（残り） | **待つ**（17 項。field が出ないと組む対象が無い） | 「service_request の activities[at0001]/description と protocol[at0008] の要素を INSTRUCTION に組む」「protocol 配下の organisation → address の 2 段の CLUSTER を、それぞれのルート名を name にして組む」「narrative の無い INSTRUCTION は組まない（または既定値）」← 5 節の問い 3 | `composition_builder.rb`、`app/lib/opt/form_capability.rb`、spec |
| E | 帳票描画: 全ルートの表示 | 新規 | **待つ**（17 項） | 「jp_referral の帳票に、パスカード 26 枚と同じ数の入力欄が出る」「入力欄がルート（SECTION → ENTRY → CLUSTER）ごとにまとまり、ルート名が見出しになる」（実ブラウザ、1280×720 で横スクロール無し） | `app/views/forms/show.html.erb`、`app/assets/stylesheets/application.css`、`docs/demo/ui-vocabulary.md`（文言を足す場合は同じコミット）、`spec/system/` |
| F | openehr-rails 0.9.0 の受け入れと迂回の撤去 | 新規（bump） | —（0.9.0 そのもの） | 22 項: 「`web_template` の field の path が、anlage の訂正なしで `[archetype_id]` 形になる」／20 項: 「0..1 の entry 配下の 1..1 の要素が required になる」／16 項: 「紹介日（context/start_time）で引ける」／23 項: 「ProblemList と jp_referral の problem_diagnosis のプロファイル id が衝突しない」 | `Gemfile.lock`、`app/models/template.rb:96-150`、`app/lib/opt/element_constraints.rb`、`app/lib/opt/rm_composition_committer.rb`、`app/controllers/fhir/profiles_controller.rb` |
| G | jp_referral v0.3 の受入 | `#23` の続き（新規） | 待たない（OPT の供給を待つ） | 「v0.3 の OPT を受け付けると、v0.2 との差分（処方・アレルギー・改名）がプレビューに出る」。golden の更新は Red ではなく実測の写し | `spec/fixtures/opt/jp_referral.opt`（**人間が供給**）、`spec/fixtures/pathcards/jp_referral.golden.json`、`docs/demo/opt-catalog.md`、`docs/reports/referral-intake-log.md` |
| H | `#23` (4) の統合 spec | `#23` | 待たない。**openehr 2.5.0**（#60）と手写像の元を待つ | 既存: 「MML 紹介状 1 通の手写像 Composition を直接コミットし、紹介先医療機関と傷病名を同じ AQL で引ける」「JP-CLINS Bundle 1 通…」（skip と pending を外す） | `spec/fixtures/compositions/jp_referral/*.canonical.json`（**人間が供給**）、`spec/integration/jp_referral_aql_spec.rb` |
| I | 出口の system spec | 新規 | D・E・2.5.0 のあと | 「jp_referral の帳票に紹介先医療機関と傷病名を入力して保存し、name 述語の AQL で 1 行引ける」（実ブラウザ） | `spec/system/demo_referral_spec.rb`（新規）、`docs/demo/aql-queries.md` |

補足:

- **A**: `rm_version` は既にある定数 `RM_VERSION`（`composition_builder.rb:61`）を使う。
  保存済みの dev データは `rake demo:reset` で作り直す（`#54` の方針）。
  保存される `rm_composition` の形が変わるので、FHIR ファサードと `spec/demo/` を regression pin にする
- **B**: B だけで jp_referral が「保存可能」に変わる可能性がある（0 field の INSTRUCTION は空 entry として
  素通しになるため。推論）。その場合、C が済むまで clinical_synopsis の 2 つは同じ値になる。
  B の PR で `FormCapability` の判定をどうするかは 5 節の問い 2
- **C と F の順序**: 22 項は「field 名を自アーキタイプで名前空間化する」変更で、C と同じ行を触る。
  0.9.0 の受け入れ（F）を先に済ませ、anlage の訂正（`rewrite_embedded_field`、`by_gem_path`）を
  撤去してから C に入る
- **D**: 構造骨格の fixture（`spec/fixtures/compositions/jp_referral/skeleton.canonical.json`）は
  INSTRUCTION に `narrative`、ACTIVITY に `action_archetype_id`（`/.*/`）を持ち、`timing` は持たない。
  帳票にこれらの入力欄は無いので、値の出どころを決める必要がある
- **E**: 「13 ルート」（ロードマップの表記）の数え方は**未確認**。本書は「パスカードの枚数と入力欄の数が一致する」を基準にした
- **F**: 0.9.0 に入る項（16・17・20〜23・25）はロードマップの記載による。25 項（template_id）は
  `docs/upstream-candidates.md` では還流先が openehr-ruby になっている。どちらで直るのかは**未確認**
- **openehr 2.5.0 の bump** は別の計画（`docs/design/openehr-2.5.0-adoption-plan.md`）。H と I の前提

## 3. 待たずに着手できるもの／待つもの

| 区分 | 項目 |
|---|---|
| いま着手できる | A（`#54`）、B（SECTION 配下の ENTRY） |
| openehr 2.5.0 の公開（11/30 の予定）を待つ | H（＋手写像の元）、I |
| openehr-rails 0.9.0 の公開（12/5 まで）を待つ | F、C、D、E |
| 人間の供給を待つ | G（v0.3 の OPT）、H（手写像の元 2 通） |

## 4. 順序と日付の案

| 日付 | 内容 |
|---|---|
| 12/1（火） | A（`#54`） |
| 12/1〜12/2 | openehr 2.5.0 の bump（棚卸しの計画が承認されていれば）。H の pending を外す |
| 12/2〜12/4 | B（SECTION 配下の ENTRY） |
| 12/5〜12/7 | F（0.9.0 の受け入れ、迂回の撤去） |
| 12/7〜12/9 | D（INSTRUCTION・多段 CLUSTER）→ C（複数ルートの区別） |
| 12/9〜12/10 | E（全ルートの表示） |
| 12/10〜12/11 | G（v0.3 の受入。OPT が 12/8 までに届いている場合） |
| 12/11〜12/12 | I（出口の system spec）、予備 |

- 余裕は 12/12 の 1 日だけ。0.9.0 が 12/5 を越えたら、D・C・E はその日数ぶん後ろにずれる
- 縮退の案: 0.9.0 が 12/8 までに出なければ、M2 の出口を「直接コミットした紹介状を
  『紹介先医療機関』で引ける」（H）に下げ、帳票からの入力（D・E・I）は公開 v0.2.0 のあとに回す
- G は出口の必須条件にしない（v0.2 の OPT で出口に届く）

## 5. 裁定と人間の入力を求める点

裁定:

1. `#30` を B・C・D の 3 つの Issue に分けてよいか（1 Issue = 1 PR にするため。`#30` は D として残す）
2. B のあと、C と D が済むまでの jp_referral の帳票の扱い。閲覧専用のままにするか、
   組める範囲（傷病名・現病歴）だけ保存可能にするか。利用者に見える結果が変わる
3. D の INSTRUCTION の `narrative`（RM で必須）と ACTIVITY の `action_archetype_id`・`timing` の値を
   どこから取るか。案: narrative は「依頼内容」の入力値、`action_archetype_id` は OPT の制約、`timing` は付けない
4. 縮退の案（0.9.0 が 12/8 までに出ない場合に出口を下げる）でよいか
5. E の「全ルート」の基準を「パスカードの枚数と入力欄の数が一致する」としてよいか

人間の入力:

1. H: 手写像の元 2 通（`mml-case1.canonical.json`・`jpclins-case1.canonical.json`）。
   元の文書（MML 紹介状 1 通、JP-CLINS 準拠 Bundle 1 通）をいつ受け取れるか。写像はセッションが行ってよいか
2. G: jp_referral v0.3 の OPT（Archetype Designer で作成）。いつ届くか
3. G: v0.3 の臨床の判断。処方の最小サブセットに入れる項目、アレルギーに使うアーキタイプ、
   「依頼内容」の改名後の名前
4. G: v0.3 で golden（`jp_referral.golden.json`）と評価のゴールドを更新する。ゴールド本体の見直しは人間

gem 側に頼む問い:

1. （openehr-rails）0.9.0 に 16・17・20・21・22・23 項のどれが入るか。25 項はどちらの gem で直すか
2. （openehr-rails）17 項の修正後、INSTRUCTION の field の path と名前はどういう形になるか
   （activities・protocol 配下、埋め込み CLUSTER の 2 段目）。D と E の spec の期待値がこれで決まる
