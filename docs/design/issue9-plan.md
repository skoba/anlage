# Issue #9 実装計画: `Opt::CompositionBuilder` の `archetype_details` 欠落修正

**作成日**: 2026-08-23
**対象Issue**: `skoba/anlage#9`
**位置づけ**: WP3（索引・検索）着手前の必須前提。`skoba/anlage#5`（デモクエリ）が
回避策で迂回した構造的ギャップの恒久解消。
**ログ**: `docs/reports/issue9-log.md`（R1〜。本計画のexplore実測記録）

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

### 3. `rm_version`の値源

- `web_template`（`Template.build_web_template`、`app/models/template.rb:59-63`）にも
  gem `FieldExtractor`出力（`field_extractor.rb:105-121`のキーは
  `archetype_id`/`rm_type`/`concept`/`fields`のみ）にも`rm_version`相当の情報源は無い
  （実測・未確認ではなく「存在しないことを確認」）。
- gem全体を横断すると`"1.0.4"`が唯一の実測リテラル値として使われている
  （`storable.rb:93,145`、`canonical_serializer.rb:41`のフォールバック、
  `graph_builder.rb:33`の`details['rm_version'] || '1.0.4'`フォールバック、
  `db/schema.rb:51`の`openehr_rm_compositions.rm_version`列デフォルト値も同じ`"1.0.4"`）。
- **決定（承認事項1）**: `Opt::CompositionBuilder`にも同じ`"1.0.4"`をリテラルで
  ハードコードする。`OpenehrRails`設定にも`web_template`にも情報源が無い以上、
  gem全体の既存慣例に合わせるのが妥当。将来複数RMバージョン対応が要る場合は
  別途Issue化する（スコープ規律）。

### 4. `template_id`の扱い

- `Archetyped#template_id`は任意（バリデーションなし）。`GraphBuilder`も
  `archetype_id`しか読まない（調査1で確認済み）ため、AQL経路には不要。
- **決定（承認事項2）**: 本Issueのスコープでは`template_id`は設定しない（省略）。
  必要になった時点で別途追加する（YAGNI、CLAUDE.mdの過剰実装禁止規律に従う）。

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

### 6. upstream-candidates.md 9項との関係

- `docs/upstream-candidates.md:259-290`（9項、`language`/`encoding`/`subject`が
  `GraphBuilder::RESERVED_KEYS`に無くクラッシュする件）は**本Issueとは独立**。
  `archetype_details`は既に`RESERVED_KEYS`に含まれておりgem側の変更は不要と判明した
  （調査1）。9項解消にはgem側`RESERVED_KEYS`拡張が必要で、それは層規律5
  （gem本体は変更しない）に抵触するため本Issueのスコープには含めない。
- したがって`spec/demo/support/height_seed.rb`/`problem_diagnosis_seed.rb`の
  回避策は2つのうち**1つ（archetype_details手動注入）のみ本Issueで撤去可能**。
  もう1つ（`NON_STRUCTURAL_ENTRY_KEYS`削除）は9項がgem側で解消されるまで残置する。

## Step 2 計画

### TDD手順（t-wada方式）

1. **Red**: `spec/lib/opt/composition_builder_spec.rb`（既存ファイルがあれば追記、
   無ければ新設）に、「`build_entry`が生成するENTRYの`archetype_details.archetype_id.value`が
   entryのarchetype_idと一致する」ユニットspecを追加。実行して失敗を確認する。
2. **Green**: `build_entry`（`composition_builder.rb:50-58`）に最小差分で
   `archetype_details:`キーワードを追加:
   ```ruby
   archetype_details: OpenEHR::RM::Common::Archetyped::Archetyped.new(
     archetype_id: OpenEHR::RM::Support::Identification::ArchetypeID.new(value: entry["archetype_id"]),
     rm_version: "1.0.4"
   ),
   ```
3. **統合Red→Green**: `spec/demo/aql_queries_spec.rb`が使う
   `spec/demo/support/height_seed.rb`から`archetype_details`手動注入行
   （`height_seed.rb:50`の`content_hash["archetype_details"] ||= ...`）を削除し、
   一旦redになることを確認してから、上記Green実装で再度通ることを確認する
   （Issue #9のAcceptance criteria2番目「手作業補完なしで通る」の直接検証）。
   `problem_diagnosis_seed.rb:37`も同様に修正する。
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

### 承認が必要な判断

1. **rm_versionはリテラル`"1.0.4"`をハードコード**（gem全体の既存慣例に合わせる。
   情報源が`web_template`にもgem設定にも無いため）
2. **template_idは本Issueのスコープでは設定しない**（AQL経路に不要、YAGNI）
3. **本Issueは`archetype_details`欠落の解消のみ**を対象とし、「フォーム保存経路が
   `CompositionCommitter`を呼んでいないためAQLに一切ヒットしない」というIssue本文の
   Impact節が示す、より大きな構造的ギャップ（WP3索引・検索の前提）は別Issueとして
   切り出す（本Issueのacceptance criteriaはarchetype_details欠落解消のみを要求して
   おり、スコープ規律上ここでは手を広げない）
4. **upstream-candidates.md 9項は独立問題として残置**（gem側変更が要るため、
   層規律5によりAnlage側では解消できない）

## Verification（Green確認後）

- `bundle exec rspec spec/lib/opt/composition_builder_spec.rb spec/demo/` が green
- `git diff`で`height_seed.rb`/`problem_diagnosis_seed.rb`から`archetype_details`
  手動注入行が消えていることを確認
- Issue #9のAcceptance criteria 3項目すべてにチェックが入る状態であることを確認
