# Issue #9 実装計画: `Opt::CompositionBuilder` の `archetype_details` 欠落修正

**作成日**: 2026-08-23
**対象Issue**: `skoba/anlage#9`
**位置づけ**: WP3（索引・検索）着手前の必須前提。`skoba/anlage#5`（デモクエリ）が
回避策で迂回した構造的ギャップの恒久解消。
**ログ**: `docs/reports/issue9-log.md`（R1〜。本計画のexplore実測記録）

> **保留中（2026-08-23、R3裁定）**: A-3実装中に`ArchetypeID`が
> `RMJSONSerializer`経由で`"value"`キーを持たずに往復する構造的不整合が判明
> （詳細: `docs/reports/issue9-log.md` R2）。シムでの回避は不採用とし、
> openehr-ruby側で修正・`2.4.2`として出荷する方針
> （`skoba/openehr-ruby#45`、`docs/upstream-candidates.md`13項）。
> **本計画（TDD手順・archetype_details供給の骨格）自体は変更不要**——
> `2.4.2` bump後にそのまま再開する。ブロック解除条件: openehr-ruby`2.4.2`
> リリース→Anlage側`bundle update openehr`→Step 2 TDD手順の再実行。

## 解決区分（CLAUDE.md「ticket-driven workflow」）

**(b) enhancement**。既存の`Opt::CompositionBuilder`は「フォーム保存経路」用に
Phase 1スコープで作られており、`archetype_details`を設定しないのは実装漏れという
より未実装機能（バグ修正というよりRMグラフ経路への対応追加）。したがって
「新規仕様のspecがまずredになり、その後green」というenhancement型で進める
（Issue本文もSymptom/Reproductionの体裁だがAcceptance criteriaは新規追加要件の形）。

## Step 1 explore 実測結果（要約。詳細根拠は `docs/reports/issue9-log.md` R1）

### 1. archetype_details欠落箇所

- `app/lib/opt/composition_builder.rb:50-58` の `build_entry` が
  `klass.new(archetype_node_id:, name:, language:, encoding:, subject:, data:)`
  を呼んでおり、`archetype_details:` を一切渡していない。
- 埋め込みC_ARCHETYPE_ROOT（入れ子CLUSTER）はこのBuilder自体が扱っていない
  （クラスコメント`composition_builder.rb:11-16`で明示的にPhase 1スコープ外、
  「flat ITEM_TREE of ELEMENTs」前提）。本計画の対象外。
- `OpenehrRails::Rm::GraphBuilder::RESERVED_KEYS`
  （gem `openehr-rails-0.4.1` `lib/openehr_rails/rm/graph_builder.rb:10-11`）は
  既に`archetype_details`を含んでおり、`build_node`（同47-62行目、特に56行目）が
  `hash.dig('archetype_details', 'archetype_id', 'value')`を明示的に読む。
  つまり**gem側は既に対応済みで、Anlage側が値を供給していないだけ**。
- `OpenehrRails::Rm::EntryNode`（gem `lib/openehr_rails/rm/nodes.rb:6-7`）が
  `validates :archetype_id, presence: true` を持ち、これが実測エラーの直接原因。

### 2. RM側の型制約（`OpenEHR::RM::Common::Archetyped::Archetyped`、gem `openehr-2.3.1`）

- `Locatable#archetype_details`（`lib/openehr/rm/common/archetyped.rb:154`）は型制約なしの
  `attr_accessor`。
- `Archetyped`（同`:201-222`）: `archetype_id`必須（`nil`で`ArgumentError`、`:211-214`）、
  `rm_version`必須（`nil`/空文字で`ArgumentError`、`:216-221`）、`template_id`は任意
  （`attr_accessor`のみ、バリデーションなし）。
- `archetype_id`への代入自体は型チェックなしだが、`Locatable#concept`
  （`archetyped.rb:187-193`）が`archetype_details.archetype_id.concept_name`を呼ぶ経路が
  あるため、実務上は`OpenEHR::RM::Support::Identification::ArchetypeID`インスタンスを渡す
  必要がある（plain stringでは`concept_name`が無く後続で壊れる）。
- `ArchetypeID.new(value: "openEHR-EHR-OBSERVATION.height.v2")`
  （`lib/openehr/rm/support/identification.rb:53-68`）は正規表現でドット区切り形式を
  検証・分解する。`entry["archetype_id"]`（`composition_builder.rb:51`で
  `archetype_node_id:`に既に使われている値）は元々この正規形式の文字列であることを
  実測確認済み（既存の`archetype_node_id:`呼び出しが成立している時点で形式は保証されている）。

### 3. `rm_version`の値源【裁定反映・A-0-1】

- `web_template`（`Template.build_web_template`、`app/models/template.rb:59-63`）にも
  gem `FieldExtractor`出力（`field_extractor.rb:105-121`のキーは
  `archetype_id`/`rm_type`/`concept`/`fields`のみ）にも`rm_version`相当の情報源は無い
  （実測・未確認ではなく「存在しないことを確認」）。
- gem全体を横断すると`"1.0.4"`が唯一の実測リテラル値として使われている
  （`storable.rb:93,145`、`canonical_serializer.rb:41`のフォールバック、
  `graph_builder.rb:33`の`details['rm_version'] || '1.0.4'`フォールバック、
  `db/schema.rb:51`の`openehr_rm_compositions.rm_version`列デフォルト値も同じ`"1.0.4"`）。
- **裁定: 承認（定数化の条件付き）**。`Opt::CompositionBuilder::RM_VERSION = "1.0.4"`と
  定数化し、定義箇所に「gem全体の唯一の実測慣例値。OPT・gem設定のいずれにも
  情報源なし」と出所コメントを付す（マジックリテラルの直書きにしない）。
  `docs/upstream-candidates.md`に12項として観察を追記する（下記）。

### 4. `template_id`の扱い【裁定反映・A-0-2、当初計画を差し戻し】

- 当初計画（省略・YAGNI）は**不承認**。裁定理由: (a) openEHR canonicalの
  Composition正規形は`archetype_details`に`template_id`を含む（`skoba/anlage#32`で
  serializerのcanonical逸脱を是正した座組と同じく、書き込み側で新たな不完全形を
  作らない） (b) パスカードidentityの第一キーが`template_id`であり、WP3で
  検索結果→Compositionを結ぶ際に必要になることが既知。
- 実測: `build_entry`は`Opt::CompositionBuilder`のインスタンスメソッドであり、
  `@template`（ivar、`composition_builder.rb:27`）に届く。`@template.web_template["template_id"]`
  は`Composition`トップレベルの`archetype_node_id:`（`composition_builder.rb:33`）に
  既に使われている値そのもの。**build_entryからtemplate参照が届かない構造ではない**
  ため、再裁定は不要——供給可能と判定。
- `Archetyped#template_id`は`attr_accessor`のみで型制約なし（調査2）だが、
  `ArchetypeID`同様のObjectID系サブクラス`OpenEHR::RM::Support::Identification::TemplateID`
  （gem `openehr-2.3.1` `identification.rb:213`、`ObjectID`を継承し`value:`のみを
  取る単純ラッパー。空文字列/nilで`ArgumentError`、`identification.rb:14-17`）が
  存在するため、`archetype_id`と対称的にこれを使う
  （`RMJSONSerializer`は任意オブジェクトを`@value`ivarからリフレクションで
  `{_type, value}`にダンプするため、`ArchetypeID`と同じ扱いで一貫性が保てる）。
- **決定（承認事項2、更新）**: `template_id: OpenEHR::RM::Support::Identification::TemplateID.new(value: @template.web_template["template_id"])`
  を`archetype_details`に設定する。

### 5. 既存データへの影響

- `app/models/composition.rb:1-7`（Anlage独自`compositions`テーブル）と
  `openehr_rm_compositions`等のRMグラフテーブルは無関係（外部キー等の接続なし、
  `db/schema.rb`実測確認）。**本Issueの修正はこの非接続構造自体を変えない**
  （Issue本文が示す「フォーム保存経路がAQLで一切ヒットしない」というより大きな
  ギャップは、`CompositionsController#create`が`CompositionCommitter`を
  呼んでいないこと自体が原因であり、別問題として本Issueのスコープ外——
  Acceptance criteriaも`archetype_details`欠落の解消のみを要求している）。
- `OpenehrRails::Rm::CompositionCommitter.commit`を呼んでいるのは現状
  `spec/demo/support/height_seed.rb:54`と`spec/demo/support/problem_diagnosis_seed.rb:41`
  のみ（`app/controllers/compositions_controller.rb:10-26`のフォーム保存経路は
  Anlage独自`compositions`テーブルへの素通し保存のみで、`CompositionCommitter`を
  呼んでいない）。したがって本Issue修正による**既存データへの後方互換影響は無い**
  （backfillは不要）。

### 6. upstream-candidates.md 9項との関係【裁定反映・A-0-4、承認】

- `docs/upstream-candidates.md:259-290`（9項、`language`/`encoding`/`subject`が
  `GraphBuilder::RESERVED_KEYS`に無くクラッシュする件）は**本Issueとは独立**。
  `archetype_details`は既に`RESERVED_KEYS`に含まれておりgem側の変更は不要と判明した
  （調査1）。9項解消にはgem側`RESERVED_KEYS`拡張が必要で、それは層規律5
  （gem本体は変更しない）に抵触するため本Issueのスコープには含めない。
- したがって`spec/demo/support/height_seed.rb`/`problem_diagnosis_seed.rb`の
  回避策は2つのうち**1つ（archetype_details手動注入）のみ本Issueで撤去可能**。
  もう1つ（`NON_STRUCTURAL_ENTRY_KEYS`削除）は9項がgem側で解消されるまで残置する。
- **裁定: 承認。ただし残置コードに撤去条件コメントを付す**。
  `NON_STRUCTURAL_ENTRY_KEYS`の定義箇所（`height_seed.rb`/`problem_diagnosis_seed.rb`
  双方）に「撤去条件: openehr-rails側`RESERVED_KEYS`拡張（台帳9項のIssue化・解消）後」
  を明記する（実装コミットに含める）。

## Step 2 計画

### TDD手順（t-wada方式）

1. **Red**: `spec/lib/opt/composition_builder_spec.rb`（既存ファイルがあれば追記、
   無ければ新設）に、「`build_entry`が生成するENTRYの`archetype_details.archetype_id.value`が
   entryのarchetype_idと一致する」ユニットspecを追加。実行して失敗を確認する。
2. **Green**: `build_entry`（`composition_builder.rb:50-58`）に最小差分で
   `archetype_details:`キーワードを追加（裁定反映済み。`RM_VERSION`定数化・
   `template_id`供給を含む）:
   ```ruby
   RM_VERSION = "1.0.4" # gem全体の唯一の実測慣例値。OPT・gem設定のいずれにも情報源なし
   ...
   archetype_details: OpenEHR::RM::Common::Archetyped::Archetyped.new(
     archetype_id: OpenEHR::RM::Support::Identification::ArchetypeID.new(value: entry["archetype_id"]),
     template_id: OpenEHR::RM::Support::Identification::TemplateID.new(value: @template.web_template["template_id"]),
     rm_version: RM_VERSION
   ),
   ```
3. **統合Red→Green**: `spec/demo/aql_queries_spec.rb`が使う
   `spec/demo/support/height_seed.rb`から`archetype_details`手動注入行
   （`height_seed.rb:50`の`content_hash["archetype_details"] ||= ...`）を削除し、
   一旦redになることを確認してから、上記Green実装で再度通ることを確認する
   （Issue #9のAcceptance criteria2番目「手作業補完なしで通る」の直接検証）。
   `problem_diagnosis_seed.rb:37`も同様に修正する。同コミットで
   `NON_STRUCTURAL_ENTRY_KEYS`（残置対象）に撤去条件コメントを付す。
4. **Refactor**: 変更なし見込み（追加行のみで既存ロジックへの影響なし）。

### 撤去可能な回避策の反映

- `height_seed.rb`/`problem_diagnosis_seed.rb`から`archetype_details`手動注入行を削除。
- `NON_STRUCTURAL_ENTRY_KEYS`削除処理（`language`/`encoding`/`subject`）は
  **残置**（upstream 9項がgem側で解消されるまで、独立の問題のため）。
- `docs/demo/aql-queries.md`冒頭の「既知の回避策2点」の記述（1-20行目）を
  「回避策1は`skoba/anlage#9`解消により撤去済み。回避策2は`docs/upstream-candidates.md`
  9項（gem側課題）として残置」に更新する。

### upstream-candidates.md 9項の帰趨

- 本Issueでは変更しない（独立問題と判定済み）。将来gem側`RESERVED_KEYS`拡張が
  upstreamで受理された場合に別途対応する。台帳のステータス行はそのまま
  「未着手（Issue起票候補）」を維持する。

### 承認が必要な判断（裁定済み・2026-08-23）

1. **rm_versionは`Opt::CompositionBuilder::RM_VERSION = "1.0.4"`として定数化**
   （出所コメント付き）。**裁定: 承認**
2. **template_idは`TemplateID.new(value: @template.web_template["template_id"])`で供給する**
   （canonical正規形整合・WP3のtemplate_idキー参照見込みのため）。**裁定: 不承認 → 設定する**
   （当初計画のYAGNI判断を差し戻し）
3. **本Issueは`archetype_details`欠落の解消のみ**を対象とし、「フォーム保存経路が
   `CompositionCommitter`を呼んでいないためAQLに一切ヒットしない」というIssue本文の
   Impact節が示す、より大きな構造的ギャップ（WP3索引・検索の前提）は別Issueとして
   切り出す。**裁定: 条件付き承認 — 実装前にA-1（経路分岐ギャップのproblem Issue）を
   起票すること**
4. **upstream-candidates.md 9項は独立問題として残置**（gem側変更が要るため、
   層規律5によりAnlage側では解消できない）。**裁定: 承認 — ただし
   `NON_STRUCTURAL_ENTRY_KEYS`に撤去条件コメントを付す**

## Verification（Green確認後）

- `bundle exec rspec spec/lib/opt/composition_builder_spec.rb spec/demo/` が green
- `git diff`で`height_seed.rb`/`problem_diagnosis_seed.rb`から`archetype_details`
  手動注入行が消えていることを確認
- Issue #9のAcceptance criteria 3項目すべてにチェックが入る状態であることを確認
