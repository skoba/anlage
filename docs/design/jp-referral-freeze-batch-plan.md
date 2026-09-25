# 凍結前バッチ計画: #29 修正 → 祖先ルート名の取り込み（#31）→ #23 (3)(4) → 契約反映

- Issue: `skoba/anlage#29`（項目 1、problem）／`skoba/anlage#31`（項目 2、goal）／`skoba/anlage#23`（項目 3、goal の (3)(4)）／項目 4 は docs（契約 v2.1 補記、本計画と同コミット）
- 状態: **承認待ち（ゲート報告 (a)）**。承認前にコードは書かない（CLAUDE.md 規律 1）
- 指示（2026-09-25、統括）: 順序固定 1→2→3→4。本文書は explore の実測結果と、各項目の TDD 手順・受入条件・承認が要る判断点をまとめる

## 0. 探索結果（実測、file:line）

1. **#29 の原因**: `app/lib/opt/pathcard_extractor.rb:52` が `C_ARCHETYPE_ROOT` の子にも `child.node_id`（常に `at0000`）を述語に使う。`content` 直下だけ `:34-38` で `archetype_id_of(root)` を使う非対称。
2. **#29 の波及は既存 golden に及ぶ**（#29 本文の「影響なし（要実測）」は誤り→Issue コメントで訂正済み）: `spec/fixtures/pathcards/LabResultReport.golden.json:53,93` の 2 カード（埋め込み `CLUSTER.laboratory_test_analyte.v1` の at0024／at0001）が `.../data[at0003]/items[at0000]/items[...]` と崩れた path のまま固定されている。修正で `items[openEHR-EHR-CLUSTER.laboratory_test_analyte.v1]` に変わる → golden 再生成 1 件（2 カード）。CardiologyEncounter／ProblemList は埋め込みルート無し（`grep 'items\[at0000\]'` で 0 件）。関連: `docs/upstream-candidates.md` 8 項（`CObject#path` の同種欠落）、`skoba/anlage#7`。
3. **祖先ルート名は gem のパース結果からは取れない**: openehr-ruby 2.4.3 `lib/openehr/am/archetype/constraint_model.rb:488-502` の `CArchetypeRoot` は `slot_node_id`／`archetype_id` のみで `term_definitions` を持たない。`lib/openehr/parser/opt_parser.rb:132-163` は各 C_ARCHETYPE_ROOT 直下の `term_definitions` を `component_terminologies[archetype_id]` に**畳み込む**（同一アーキタイプの複数ルートでは 1 件に潰れる。実測: jp_referral の organisation ×5 は全て「診療科」、person ×3 は全て「担当医」に見える）。runtime 確認: 13 ルートとも `term_definitions` は nil（scratch、`Opt::SafeParser.parse` → walk）。
4. **per-root の at0000 名は OPT XML にはある**: 各 `C_ARCHETYPE_ROOT` 要素直下の `term_definitions[@code='at0000']/items[@id='text']`（R4 で Nokogiri 実測: 紹介元医療機関／紹介先医療機関／診療科／担当医／医師／傷病名／既往歴及び家族歴／症状経過及び検査結果／治療経過／紹介状の詳細情報／サービス依頼）。
5. **検索の索引対象**: `app/lib/opt/pathcard_search.rb:29-38` `searchable_texts` = labels + descriptions + code_list labels。bigram は `:40-42`。
6. **golden の形**: `{"_provenance": {source_fixture, source_sha256, binding_origin}, "cards": [...]}`、比較は `spec/lib/opt/pathcard_extractor_golden_spec.rb`（`provenance` 除去・SNOMED 1 件以外の code を伏せる `normalize_for_golden`、件数固定 `GOLDEN_CASES`）。再生成は scratch（`wp3-log` R2 の手順どおり: 抽出 → normalize → `_provenance` 付与 → git diff で目視）。
7. **評価ハーネス**: `lib/tasks/pathcards.rake` `pathcards:eval`（17 問 `spec/fixtures/pathcards_eval_seed.yml`、`docs/reports/wp4-eval-log.md` へ追記）。直近値 Top-1 14/17・Top-3 15/17・MRR 0.8529（2026-08-26）。dev DB のテンプレートに対して走る（fixture 5 件 + jp_referral が登録済み）。
8. **名前衝突掃引**: `container_labels`／`container` は `app/ lib/ spec/ docs/design/` に不在（`wp0-exploration.md:738` の英文引用のみ）。スキーマ v1.1 の `semantics` 直下キーは `rm_type`／`rm_type_alternatives`／`labels`／`descriptions`。
9. **(4) の直接コミット経路**: `OpenehrRails::Rm::CompositionCommitter.commit(hash, uid:, owner: nil)`（R6 で実測、SECTION／INSTRUCTION 入りでも commit 自体は通る）。`to_rm`／AQL は上流 15 項で落ちる。テストは `use_transactional_fixtures = true`（`spec/rails_helper.rb:58`）なので example 単位で rollback され、他 spec の AQL を汚さない。

## 1. 項目 1: #29 修正（解決形 (a) bug、TDD）

テスト TODO:

- [ ] Red 1: `spec/lib/opt/pathcard_extractor_spec.rb` に「SECTION 配下の埋め込みルートを archetype_id 述語で書く」——jp_referral.opt の at0121 カードの path が `/content[openEHR-EHR-SECTION.referral_details.v0]/items[openEHR-EHR-INSTRUCTION.service_request.v1]/activities[at0001]/description[at0009]/items[at0121]/value` であること。実行して失敗を確認
- [ ] Red 2: 入れ子 CLUSTER（紹介先の担当医 at0001）の path が `.../protocol[at0008]/items[openEHR-EHR-CLUSTER.organisation.v1]/items[openEHR-EHR-CLUSTER.organisation.v1]/items[openEHR-EHR-CLUSTER.person.v1]/items[at0001]/value` であること
- [ ] Green: `walk` `:52` を `node_path << "[#{archetype_id_of(child) || child.node_id}]"` に（最小変更）
- [ ] pin: jp_referral 26 カードの path に `[at0000]` が 1 つも含まれず、件数 26（regression pin ではなく Green 後の性質固定。Red 1・2 と同じ commit）
- [ ] golden 再生成: `LabResultReport.golden.json`（2 カードの path のみ差分であることを git diff で確認、`_provenance` 不変）
- [ ] 全 suite green・rubocop 0

fixture: `spec/fixtures/opt/jp_referral.opt` を**本項目で導入**する（byte 同一、sha256 `99d474f8…d62fa`、opt-catalog を「fixture 化済み」へ）。理由: Red spec に SECTION 入りの実物 OPT が要り、reduced fixture を作るより real を使う方が規律 3 に沿う。#23 (3) の fixture 化はこれで前倒しになる（golden は項目 3）。

## 2. 項目 2: 祖先ルート名の取り込み（goal #31、解決形 (b) enhancement）

### スキーマ v1.2（additive）

```yaml
semantics:
  container_labels:            # v1.2 追加。祖先 C_ARCHETYPE_ROOT（SECTION／ENTRY／CLUSTER）の
    - lang: "ja"               #   テンプレート名（各ルート直下 term_definitions の at0000 text）を
      text: string             #   ルートから葉へ向かう順に並べる。COMPOSITION 自体は含めない。
      archetype_id: string     #   labels と同じ未翻訳検出フィールドを持つ（同じ classify_translation）
      untranslated_suspect: boolean
      untranslated_evidence: "fallback_marker" | "no_ja_script" | null
      source_lang: string | null
```

例（紹介先担当医の氏名カード）: `[紹介状の詳細情報, サービス依頼, 紹介先医療機関, 診療科, 担当医]`。既存 fixture の例（LabResultReport 分析項目）: `[検査結果報告（at0000 名）, （CLUSTER.laboratory_test_analyte の at0000 名）]`——実値は再生成時に実測。

`schema_version` は `"1.2"` へ、`Opt::PathcardExtractor::VERSION` は `wp2-0.2.0` へ。v1.1 カードは `container_labels` 欠落として読める（v1.0→v1.1 と同じ additive 規約）。

### 取り込み元（承認が要る判断 A）

gem のパース結果に per-root 名が無い（探索 3）ため、選択肢:

- **案 a（推奨）**: 抽出器が `@template.source_xml` を Nokogiri で再解析し、各 `C_ARCHETYPE_ROOT` の at0000 text を **RM path＋同 path 内の出現順** をキーに引く（`#29` 修正後の path と同じ規則で Nokogiri 側も path を組む。紹介元／紹介先のように同一 path に同一アーキタイプが並ぶ場合は出現順で結ぶ）。`Opt::SafeParser` を通った XML のみを読むので XXE 面は既存経路と同等。**撤去条件**をコード注記に置く: openehr-ruby が `CArchetypeRoot#term_definitions` を持つようになった時点で gem 経路へ置換（`docs/upstream-candidates.md` 18 項）。WP2 の「経路2」（`#19` で撤去した term_bindings 再解析）と同型だが、今回は gem 側に代替経路が**存在しない**点が異なる
- 案 b: openehr-ruby 側を先に直す（`CArchetypeRoot` に per-root `term_definitions` を持たせる）。越境実装＝規律 9 のゲート。リリース（2.4.4）と anlage の bump を挟むため凍結前バッチには乗りにくい
- 案 c: 畳み込まれた `component_terminologies[archetype_id]` の at0000 を使う。同一アーキタイプ複数ルートで**誤った名前**になる（紹介元が「診療科」）ため不採用

### 検索

`Opt::PathcardSearch#searchable_texts` に `container_labels` の text を加える（`:29-38`）。スコアは既存どおり bigram の OR 一致数（重み付けはしない。v1.2 は「着地すること」が目的）。

### テスト TODO

- [ ] Red: 抽出器 spec「jp_referral の担当医氏名カードの container_labels が 5 段の連鎖」／「LabResultReport の分析項目カードの container_labels が宿主名＋CLUSTER 名」／「content 直下 ENTRY の葉は 1 段」
- [ ] Red: 同一アーキタイプ複数ルートの区別（紹介元医療機関の名称カード → `紹介元医療機関`、紹介先 → `紹介先医療機関`）
- [ ] Green: 案 a の実装（Nokogiri 再解析ヘルパー＋walk で祖先スタックを持ち回る）
- [ ] Red→Green: 検索 spec「既往歴」「傷病名」「治療経過」「紹介先」が jp_referral カードに着地（golden から登録して検索）
- [ ] golden 再生成 4 件（Cardiology／Lab／Problem／jp_referral）: 差分が `schema_version` と `container_labels` 追加のみであることを git diff で確認
- [ ] `pathcards:eval` を dev で実行し、17 問の Top-1／Top-3／MRR・各問の rank が**直前の記録と同一**であることを確認（`wp4-eval-log.md` へ追記。変化があれば例外報告——container_labels の bigram が既存問の順位を動かした場合は裁定）
- [ ] `docs/design/pathcards-schema-v1.md` に v1.2 節（設計判断 10）を追記
- [ ] UI（`app/views/pathcards/_pathcard.html.erb`）への表示は**対象外**（スコープ規律 8。必要なら別 goal）

### 受入条件（Issue #31 と同文）

- [ ] 抽出器が `semantics.container_labels` を出し、`schema_version` が `"1.2"`（spec green）
- [ ] 検索が container_labels を索引し、「既往歴」「傷病名」「治療経過」「紹介先」が jp_referral のカードに着地する（spec green）
- [ ] golden 4 件再生成、差分は additive のみ
- [ ] `pathcards:eval` 17 問の結果が不変（`wp4-eval-log.md` の追記で証明）

## 3. 項目 3: #23 (3)(4)

### (3) fixture・golden・保留問

- fixture は項目 1 で導入済み。golden `spec/fixtures/pathcards/jp_referral.golden.json`（26 カード、`_provenance` に `source_fixture`／`source_sha256`／`binding_origin: "CKM公開束縛由来"`（束縛 0 件だが形を揃える）／追加で `source_repository: skoba/openehr-templates-jp@8eebe04…`）。`GOLDEN_CASES` に `count: 26` を追加
- 保留問 2 件（承認が要る判断 B）: 「既往歴→story」は container_labels 後に着地するので **q21 として下書き追加**（`expected_archetype_id: OBSERVATION.story.v1`、`intent_tag: 節名`（新タグ）、`reviewed_by` 空欄——ゴールド本体は人間レビュー領域なので、追加自体を承認事項とする）。「検体→CLUSTER.specimen」は v0.3 まで該当カードが無く**出題不能**（見送り、理由を seed 注記に残す）
- opt-catalog を「fixture 化済み・golden 26」へ

### (4) 統合 spec（直接コミット経路）

- 置き場: `spec/integration/jp_referral_aql_spec.rb`（`type: :request` ではない。`OpenehrRails::Rm::CompositionCommitter.commit` → `OpenehrRails::Aql::Executor.execute`）
- 入力: 手写像 canonical JSON 2 通 `spec/fixtures/compositions/jp_referral/mml-case1.canonical.json`／`jpclins-case1.canonical.json`。**人間供給が前提**（承認が要る判断 C）: 実 MML 紹介状 1 通と JP-CLINS 準拠 Bundle 1 通（NoEntry 作例可）を統括から受け取り、契約 §6 の写像方針で Claude Code が手写像する。fixture 種別は「reduced（実文書からの手写像）」、個人情報は含めない（作例値）
- 主張: 両通から `CONTAINS COMPOSITION c[openEHR-EHR-COMPOSITION.request.v1] CONTAINS INSTRUCTION i[...service_request.v1]` で紹介先医療機関（name 述語）・傷病名・既往歴が同じ AQL で引ける（期待行数一致）
- **上流 15 項（`RmObjectBuilder::TYPE_CLASSES`）の解消待ちを spec 内で明記**: `pending "openehr-rails 上流候補 15 項（SECTION/INSTRUCTION の to_rm）解消待ち"` で書く。現状は `NoMethodError` で pending 扱い、解消後に自動で失敗→pending 削除。16 項（context 未永続化）は紹介日クエリを含めないことで回避（含めるなら同様に pending）
- 凍結受入条件との関係: `spec/demo/` には入れない（凍結条件は現行 4 クエリのまま）。デモ役割の縮退は契約 §8 補記のとおり

## 4. 項目 4: 契約 v2.1 補記（本コミットで実施、docs のみ）

`docs/design/referral-v2-inventory.md` §2・§3.1・§8・§10 に 2026-09-25 の人間裁定を反映: 症状経過＝clinical_synopsis 確定、名前判別（name 述語）確定、紹介目的＝at0062 確定、デモ役割の縮退、上流 15〜17 の相互参照。

## 5. 承認が要る判断（ゲート）

- **A**: container_labels の取り込み元＝案 a（Nokogiri 再解析＋撤去条件）で進めてよいか（案 b は越境ゲート＋リリース待ち）
- **B**: 保留問「既往歴→story」を q21 として seed に下書き追加してよいか（人間レビュー領域）。「検体」は見送り
- **C**: (4) の手写像元（MML 紹介状 1 通・JP-CLINS Bundle 1 通）の供給。届くまで (4) は spec 骨格＋pending のみ
- **D**: jp_referral.opt fixture を #29 のコミットで先に入れる（#23 (3) の前倒し）ことの可否
- 承認後の順序: 項目 1（1〜2 コミット）→ 項目 2（2〜3 コミット、`Refs #31`）→ 項目 3（golden・seed・spec 骨格、`Refs #23`）。各項目の完了で `referral-intake-log.md` R7〜 に記録、push SHA・CI run をバンドル報告に含める
