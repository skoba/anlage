# #9（CompositionBuilder の archetype_details 欠落修正）進行ログ

explore→planフェーズの実測記録。R1〜。

---

## R1: Step 1（explore）

### 1. archetype_details欠落箇所の実測

`app/lib/opt/composition_builder.rb:50-58`の`build_entry`が
`klass.new(archetype_node_id:, name:, language:, encoding:, subject:, data:)`を
呼んでおり、`archetype_details:`を一切渡していない。埋め込みC_ARCHETYPE_ROOT
（入れ子CLUSTER）はこのBuilder自体が扱っていない（クラスコメント
`composition_builder.rb:11-16`「flat ITEM_TREE of ELEMENTs」、Phase 1スコープ外）
ため対象外。

gem`openehr-rails-0.4.1`側は既に対応済みと判明: `GraphBuilder::RESERVED_KEYS`
（`lib/openehr_rails/rm/graph_builder.rb:10-11`）に`archetype_details`が既に含まれ、
`build_node`（同47-62行目、56行目）が`hash.dig('archetype_details', 'archetype_id', 'value')`
を明示的に読む実装になっている。`EntryNode`（`lib/openehr_rails/rm/nodes.rb:6-7`）の
`validates :archetype_id, presence: true`が実測エラーの直接原因。

**結論: gem側の変更は不要。Anlage側`composition_builder.rb`が値を供給していないだけ。**

### 2. RM側の型制約実測（`openehr-2.3.1`）

- `Locatable#archetype_details`（`lib/openehr/rm/common/archetyped.rb:154`）: 型制約なし
- `Archetyped`（同`:201-222`）: `archetype_id`必須（nilで`ArgumentError`、`:211-214`）、
  `rm_version`必須（nil/空文字で`ArgumentError`、`:216-221`）、`template_id`任意
- `archetype_id`は`ArchetypeID`インスタンスが実務上必須（`Locatable#concept`が
  `concept_name`を呼ぶ経路があるため、plain stringでは後続で壊れる）
- `ArchetypeID.new(value: "openEHR-EHR-OBSERVATION.height.v2")`
  （`lib/openehr/rm/support/identification.rb:53-68`）は正規形式を検証・分解する。
  `entry["archetype_id"]`（`composition_builder.rb:51`で既に`archetype_node_id:`に
  使われている値）は既にこの正規形式であることを、既存呼び出しの成立自体から確認済み

### 3. rm_versionの値源実測

`web_template`（`app/models/template.rb:59-63`）にもgem`FieldExtractor`出力
（`field_extractor.rb:105-121`、キーは`archetype_id`/`rm_type`/`concept`/`fields`のみ）
にも情報源なし（存在しないことを確認）。gem全体で`"1.0.4"`が唯一の実測リテラル値
（`storable.rb:93,145`、`canonical_serializer.rb:41`、`graph_builder.rb:33`の
フォールバック、`db/schema.rb:51`列デフォルト値も同値）。→ 計画では同リテラルを
Anlage側にもハードコードする方針とした（承認事項1）。

### 4. 既存データへの影響

`app/models/composition.rb`（Anlage独自`compositions`テーブル）と
`openehr_rm_compositions`等は無接続（`db/schema.rb`実測）。本Issueの修正はこの
非接続構造自体を変えない。`CompositionCommitter.commit`を呼ぶのは現状
`spec/demo/support/height_seed.rb:54`・`problem_diagnosis_seed.rb:41`のみ
（`app/controllers/compositions_controller.rb:10-26`のフォーム保存経路は
`CompositionCommitter`を呼ばず、Anlage独自テーブルへの素通し保存のみ）。
**既存データへの後方互換影響なし（backfill不要）。**

### 5. upstream-candidates.md 9項との関係実測

`docs/upstream-candidates.md:259-290`（9項、`language`/`encoding`/`subject`が
`RESERVED_KEYS`に無くクラッシュする件）は本Issueと独立と判定。`archetype_details`は
既に`RESERVED_KEYS`に含まれる（上記1）ためgem側変更は不要だが、9項解消には
`RESERVED_KEYS`拡張というgem側変更が必要で、層規律5に抵触するため本Issueの
スコープには含めない。→ `height_seed.rb`/`problem_diagnosis_seed.rb`の回避策2点の
うち、archetype_details手動注入のみ本Issueで撤去可能。`NON_STRUCTURAL_ENTRY_KEYS`
削除処理は残置。

### Step 2への引き継ぎ

計画書は`docs/design/issue9-plan.md`に作成。承認事項4点（rm_versionリテラル化・
template_id省略・スコープをarchetype_details欠落解消に限定・upstream 9項は独立残置）
を明記し、ゲート報告で承認を仰ぐ。
