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
