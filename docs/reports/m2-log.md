# M2（書き込みの完成）の進行ログ

計画: `docs/design/m2-plan.md`（承認済み、R-20261124-5）。作業列: R-20261124-10（anlage、書く側）。
進め方: R-20261124-8（`CLAUDE.md`「全開の進め方」）。

## R1 A（`skoba/anlage#54`）: ルートの archetype_node_id と archetype_details（2026-11-24）

ブランチ `fix/54-composition-root-archetype`。基準点は main `6c100e0`。

### 自己承認した判断

1. **ルートの archetype_id は登録時に `web_template["root_archetype_id"]` に入れ、キーが無い登録済みの
   テンプレートでは `source_xml` から引く**（`Template#root_archetype_id`）。
   - 採った理由: `web_template` は登録時に固定され、開発機には #54 より前に登録したテンプレートがある。
     フォールバックが無いと、それらで保存するたびに nil のルートを組む。データの移行は「必ず止まる」に
     当たるので、移行なしで動く形にした
   - 捨てた案: (a) 毎回 `source_xml` を解析する（保存のたびに OPT を解析する。登録時に固定する既存の
     方針と合わない）。(b) `rake templates:rebuild_web_template` を前提にする（開発機のデータを書き換える操作を
     利用者に求めることになる）
   - 根拠（実測）: `Opt::SafeParser.parse(jp_referral.opt).definition.archetype_id.value` は
     `"openEHR-EHR-COMPOSITION.request.v1"`、`definition.rm_type_name` は `"COMPOSITION"`
     （openehr 2.4.3、`lib/openehr/parser/opt_parser.rb:117-119` の `definition` が `c_archetype_root` を返す）
2. **Composition の JSON のドロップ（`TemplatesController#preview_composition`）の照合を
   `archetype_details.template_id` に改め、以前の形も受け付ける**。
   - 理由: これまではルートの `archetype_node_id` を template_id として引いていた
     （`app/controllers/templates_controller.rb:106`）。A のあとは COMPOSITION アーキタイプの ID が入るので、
     そのままだと「記入済みの帳票」のプレビューが必ず失敗する。計画書の「触るファイル」には無いが、
     A の変更がそのまま壊す箇所なので同じ PR で直した
   - 以前の形（`archetype_details` 無し、`archetype_node_id` が template_id）の受け付けは spec で pin した

### Red（実装の前、`bundle exec rspec` 3 ファイル、25 例 4 失敗）

```
1) Opt::CompositionBuilder 日本語前提の既定値 ルート（COMPOSITION） archetype_node_id は COMPOSITION アーキタイプの ID になる（template_id ではない）
     expected: "openEHR-EHR-COMPOSITION.encounter.v1"
          got: "CardiologyEncounter"
2) … archetype_details に archetype_id、template_id、RM version を持つ
     NoMethodError: undefined method 'archetype_id' for nil
3) … root_archetype_id を持たない登録済みの web_template（#54 より前の登録）でも、OPT から引いて組む
     expected: "openEHR-EHR-COMPOSITION.encounter.v1"
          got: "CardiologyEncounter"
4) Forms and Compositions POST /compositions/:template_id フォームから保存すると、RM グラフの template_id 列に template_id が入る
     expected: ["patient_blood_pressure.v1"]
          got: [nil]
```

以前の形のドロップを受け付ける spec は、実装の前から緑（regression pin）。

### Green

- 開発機の全 suite: 249 例 0 失敗、3 pending（pending は `#23` (4) の 3 件で、前から変わらない）
- regression pin: `spec/demo/`、`spec/requests/fhir_profiles_spec.rb`、`spec/tasks/demo_reset_spec.rb` の 11 例 0 失敗
- `spec/tasks/demo_reset_spec.rb` は、RM 側を template_id 列でも見るように足した
  （6 件すべてに template_id が入る。これまでは「nil になる既存の欠陥」と注記していた）

### 開発機のデータ

- 既に登録済みのテンプレートは、そのまま使える（上の判断 1 のフォールバック）
- 既に保存済みの Composition は以前の形のまま残る。新しい形にそろえるには `rake demo:reset`。
  セッションは実行していない（R-20261124-5）

### 残り

- 上流候補 25 項（AQL から `c/archetype_details/template_id/value` に届かない）は別件で、この PR では変わらない。
  `docs/demo/aql-queries.md:116` の「出所の並記は Composition 名」はそのまま

## R2 B（`skoba/anlage#80`）: SECTION 配下の ENTRY を組む（2026-11-24）

ブランチ `feat/80-section-entries`。基準点は main `6dac631`（A のマージのあと）。
Issue `#80` を `#30` から分けて起票した（R-20261124-5 問い 1）。

### 自己承認した判断

1. **fixture は jp_referral.opt（実物）を使い、値を入れる entry を選んで衝突を避けた**。
   - 裁定は「SECTION を持ち複数ルートの衝突が無い fixture で確かめる」。そういう OPT は手元に無い
     （`spec/fixtures/opt/` で SECTION を持つのは jp_referral.opt だけ。実測: `grep -c SECTION`）。
     OPT を作るのは人間の領域なので、作っていない
   - builder の spec: jp_referral に、傷病名（EVALUATION）と現病歴（OBSERVATION）だけ値を入れる。
     空欄の entry は組まれない（#34）ので、INSTRUCTION と clinical_synopsis ×2 は関わらない
   - 保存可否の spec: jp_referral の `web_template` から、INSTRUCTION と 2 つめの clinical_synopsis を除いた形
     （実物からの導出。at-code・path は変えていない）で `saveable` になることを確かめた
   - **できていないこと**: SECTION を持つテンプレートの、帳票からの POST の通し（request spec）。
     保存可能な実物の OPT が要る。人間への依頼として下に書いた
2. **保存可否の判定に、ドライランでは見えない理由を足した**（`CompositionBuilder#unsupported_reasons`）。
   - (a) builder が組めないクラスの entry（jp_referral の INSTRUCTION は field が 0 で、ドライランでは
     空 entry として飛ばされる）。(b) 複数の field で衝突する名前（clinical_synopsis ×2）
   - 判定規則は builder に置き、`FormCapability` は尋ねるだけにした（規則を二重に持たない、#36 の方針）
   - 捨てた案: `build` の中で常に検査する（保存のたびに走る。保存時の挙動を変えたくない）
   - 理由が複数あるときは `; ` でつなぐ。jp_referral の理由は
     `entry rm_type INSTRUCTION is not supported yet; field name clinical_synopsis is shared by 2 fields` になる
     （これまでは `unexpected wrapper depth for EVALUATION`）
3. **SECTION の name は、テンプレート上の名前を `web_template["section_labels"]` から取る**
   （`Opt::TemplateTerms` の結果から、登録時に入れる。jp_referral では「紹介状の詳細情報」で、
   構造骨格の fixture と同じ）。キーが無い登録済みの web_template では、アーキタイプ ID の概念名に落とす
4. **reader と committer も SECTION を辿るようにした**（計画書の「触るファイル」には無い）。
   - committer: SECTION の中の ENTRY から非構造キー（language・encoding・subject）を外さないと、
     RM グラフへのコミットが `unknown RM node type "CODE_PHRASE"` で落ちる（実測。下の Red の 3 つめの次に出た）
   - reader: builder が組める形は読み戻せるようにそろえた

### Red（実装の前、`composition_builder_spec.rb` と `template_spec.rb`、5 失敗）

```
1) Opt::CompositionBuilder#80 SECTION 配下の ENTRY content には SECTION が 1 つ入り、archetype_node_id・テンプレート上の名前・archetype_details を持つ
     Opt::CompositionBuilder::UnsupportedShape: unexpected wrapper depth for EVALUATION
2) … SECTION 配下の EVALUATION と OBSERVATION を、SECTION の items に入れて組む
     Opt::CompositionBuilder::UnsupportedShape: unexpected wrapper depth for EVALUATION
3) … 組んだ Composition を RM グラフにコミットでき、SECTION 越しの path で引ける
     Opt::CompositionBuilder::UnsupportedShape: unexpected wrapper depth for EVALUATION
4) Template#36 form_capability jp_referral は、SECTION 配下の ENTRY を組めるようになっても preview_only のまま（INSTRUCTION と field 名の衝突）
     expected "unexpected wrapper depth for EVALUATION" to include "INSTRUCTION"
5) Template#36 form_capability SECTION 配下の ENTRY だけで、field 名の衝突が無ければ saveable
     expected: {"form_capability" => "saveable", "form_capability_reason" => nil}
          got: {"form_capability" => "preview_only", "form_capability_reason" => "unexpected wrapper depth for EVALUATION"}
```

reader の Red（builder の実装のあと）:

```
Opt::CompositionReader#80 SECTION 配下の ENTRY builder が SECTION の items に入れた EVALUATION と OBSERVATION の値を読み戻す
     expected: {"problem_diagnosis_at0002" => "高血圧症", "story" => "3 か月前から頭痛"}
          got: {}
```

「content 直下の ENTRY は従来どおり」は実装の前から緑（regression pin）。

### Green

- 開発機の全 suite: 255 例 0 失敗、3 pending（pending は R1 と同じ 3 件）
- rubocop: 違反なし

### 見つけたもの

- **`skoba/anlage#82`**（既存の不具合、この PR では直していない）: `coded_free` で保存した値（DV_TEXT）を
  reader が読み戻せない。ProblemList（content 直下）でも `{"problem_diagnosis_at0002" => nil}` になる（実測）。
  reader の spec は、これを避けて診断確度（at0073、選択肢）と現病歴で書いた

### 人間への依頼

- SECTION を持ち、未対応クラスの entry も複数ルートの衝突も無い OPT を 1 つ（Archetype Designer で作成）。
  届けば、帳票からの POST の通しの spec を足す。無くても C・D のあとは jp_referral で通しを確かめられる

## R3 作業列 4: 帳票に入力欄の無い RM の属性の設計書（2026-11-24）

ブランチ `docs/rm-attributes-without-inputs`。基準点は main `c09d72f`（B のマージのあと）。
成果物は `docs/design/rm-attributes-without-inputs.md`。

### ゲート報告（narrative の作り方。人間の判断）

設計書 6 節。候補は 4 つ（A: 1 項目の写し、B: 複数項目からの組み立て、C: 専用の入力欄、D: 固定文）。
推奨は B。決めてほしい点は 3 つ:

1. A〜D のどれを採るか（B に C を重ねる形もありうる）
2. B の場合、つなぎ方（区切り、含める型、空欄の扱い）を実装で決めてよいか
3. 「依頼内容」がどの要素を指すか（B なら決めなくて済む）

D（INSTRUCTION を組む作業）は、この答えと openehr-rails 0.9.0 の両方を待つ。ほかの作業は止めない。

### 実測で見つけた欠陥（設計書 4 節）

1. 保存される CODE_PHRASE の `terminology_id` が、すべて値を持たない（`{"_type":"TERMINOLOGY_ID"}`）。
   `TerminologyID.new(name:)` で組んでいるため。上流候補 26 項に観察を書いた
2. COMPOSITION の `category` の値とコードが逆（`value` が `"433"`、`code_string` が `"event"`）。
   gem の検査は常に true を返すので通っていた。上流候補 27 項
3. HISTORY・EVENT・ITEM_TREE・ENTRY の name が、テンプレートの用語でない（固定文と英字の concept）
4. `context` が付かない（上流候補 16 項と同じ件）

### 自己承認した判断

- 1〜3 は、設計書 5 節の順（1 → 2 → 3 → 4）で、1 Issue = 1 PR で直す。保存される Composition の形を
  変えるので、A（`#54`）と同じ扱いにする（保存済みの記録は変えない、`spec/demo/` と FHIR を regression pin）。
  R-20261124-10 の「ほかの属性の扱いは、設計書に書いたとおりに進めてよい」による
- 3（name）は、name 述語の AQL と検索に影響しうるので、着手の前に洗ってログに書く

## R4 `skoba/anlage#86`: terminology_id に値を入れる（2026-11-24）

ブランチ `fix/86-terminology-id-value`。設計書 5 節の 1。

### Red（実装の前、3 失敗）

```
1) Opt::CompositionBuilder#86 terminology_id の値 COMPOSITION の言語・地域・category の terminology_id が値を持つ
     expected: "ISO_639-1"
          got: nil
2) … ENTRY の言語・文字コードの terminology_id が値を持つ
     expected: "ISO_639-1"
          got: nil
3) … 選択肢（DV_CODED_TEXT）の terminology_id が値を持つ
     expected {"_type" => "CODE_PHRASE", "code_string" => "at0074", "terminology_id" => {"_type" => "TERMINOLOGY_ID"}}
     to include {"terminology_id" => {"_type" => "TERMINOLOGY_ID", "value" => "local"}}
```

### Green

- 変更は 1 行（`code_phrase` が `TerminologyID.new(value:)` で組む）
- 開発機の全 suite: 258 例 0 失敗、3 pending。`spec/demo/` と FHIR の spec は緑のまま（regression pin）

## R5 作業列 3（`skoba/anlage#90`）: openehr 2.4.3 → 2.5.0（2026-11-24）

ブランチ `chore/90-openehr-2.5.0`。基準点は main `91715f0`。計画は
`docs/design/openehr-2.5.0-adoption-plan.md` 4 節の 1（承認済み、R-20261124-4）。**マージは人間**（依存を変える PR）。

### 着手の条件（実測）

- RubyGems の openehr 2.5.0: sha256 `8eb126bfda72a16aeb608f2fba9e4259aca95800196e0b21136d9eb3ed42f10b`
  （`https://rubygems.org/api/v1/versions/openehr.json`、公開は 2026-11-24T12:18:23Z）
- 上流の記録（skoba/openehr-ruby `86f9f8a` の `docs/reports/round2-log.md` R4、138 行）の値と一致
- 2.5.0 に入った項目（タグ `v2.5.0` の `History.txt`）: #60・#31・#43・#48・#58・#49 の 6 件。#59 は入っていない

### 自己承認した判断

1. **`Gemfile.lock` は、openehr の 2 行（版と checksum）だけを書き換えた**。
   `bundle update openehr --conservative` は、nokogiri・sqlite3・mini_portile2 の行（プラットフォーム別の行）まで
   消した（11 行減）。裁定は「変えるのは `Gemfile.lock` と計画書 1 節の spec・文書だけ」なので、lock を戻して
   2 行だけ直し、`bundle install` が lock を変えずに通ることを確かめた。2.4.3 と 2.5.0 の実行時の依存は同じ（`gem spec` の比較）
2. **デモ Q2 も本来形に置き換えた**（#49 が 2.5.0 に入ったため。R-20261124-4 問い 2）
3. **実ブラウザの system spec（`spec/system/demo_problem_list_spec.rb`）のクエリも、Q2 の本来形にそろえた**。
   この spec は「デモクエリ 2 と同じ MATCHES」と書いていて、計画書 1 節の一覧には無い。期待する行は変えていない
4. **`README.md` の依存の行を実際の版に直した**（2.5.0／0.8.0。これまでの記載は 2.4.3／0.7.1 で、0.8.0 への更新が漏れていた）
5. **`Opt::TemplateTerms` の撤去は混ぜていない**（#58 は入った。計画書 4 節の 3 のとおり、次の別の PR）

### Red

lock を 2.5.0 にした直後の全 suite（258 例 1 失敗 2 pending）。pending が通るようになったことを RSpec が失敗として知らせる:

```
rspec ./spec/integration/jp_referral_aql_spec.rb:54 # jp_referral: 手動写像 Composition からの AQL 統一性（#23 (4)） 構造骨格（実 at-code）を直接コミットし、紹介先医療機関を name 述語で引ける
```

デモ Q2・Q4 の本来形は、lock を 2.4.3 に戻して Red を確かめた:

```
1) デモクエリ（フォーム保存経路経由） 2. MATCHES 値リスト（コード値の複数一致） …
     OpenehrRails::Aql::UnsupportedFeature:
       unsupported path attribute "defining_code" on a OpenEHR::RM::DataTypes::Text::DvCodedText
2) デモクエリ（フォーム保存経路経由） 4. 日付範囲WHERE（期間絞り込み） OBSERVATION のイベント時刻が期間内の Composition のみ期待件数（1件）で抽出できる
     OpenehrRails::Aql::UnsupportedFeature:
       unsupported path attribute "time" on a OpenEHR::RM::DataStructures::History::PointEvent
```

### Green（2.5.0）

- 開発機の全 suite: 258 例 0 失敗、2 pending（残る 2 件は手写像の元が未供給の skip。人間の入力待ち）
- regression pin: golden 4 件、`spec/models/template_spec.rb`、`spec/demo/`、実ブラウザの system spec は、
  期待値を変えずに緑（Q2・Q4 と上の 3 を除く）
- rubocop: 違反なし

### 計画書 3 節の「未確認」の結果

1. #60: openehr-rails 0.8.0 の実行系を通しても name 述語が効く（上の Red がその証拠。`[ "X病院", "2型糖尿病" ]` を返す）
2. #43: openehr-rails 0.8.0 の `FieldExtractor` の path は変わらない（`template_spec.rb` と golden が無変更で緑）
3. #31: code_binding は同じ内容（golden が無変更で緑）

### 次

- `Opt::TemplateTerms` の撤去（#58）。この PR のマージのあとに、別の Issue と PR で
- H（`#23` (4)）の残り 2 件は、手写像の元を待つ
