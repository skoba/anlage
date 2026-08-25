# FSHエクスポート 進行ログ

explore→planフェーズの実測記録。R1〜。goal Issue: `skoba/anlage#17`。

---

## R1: Step 1（explore、実測）

### 1. 既存FHIRファサードの内部構造

`app/controllers/fhir/profiles_controller.rb:24-29`（anlage）は
`OpenehrRails::Opt.parse(template.source_xml)`でOPTを都度パースし、
`OpenehrRails::Fhir::ProfileGenerator.new(opt).profiles`を呼ぶだけ——
**永続化された中間表現は無い**。gem側`ProfileRepository.from_registry`
（`openehr-rails` `lib/openehr_rails/fhir/profile_repository.rb:26-33`）も
同型で、リクエストの都度OPTから再構築する。

`ProfileGenerator`（`openehr-rails` `lib/openehr_rails/fhir/profile_generator.rb:18-21`）
は自身ではOPTを歩かず、`OpenehrRails::Opt::FieldExtractor.new(template).entries`
（`lib/openehr_rails/opt/field_extractor.rb:50-51`）を唯一の入力として使う。
`FieldExtractor#entries`はモデル生成・マイグレーション生成（M1）・
FHIR生成（M2/M3、`ResourceRegistry`/`Serializer`も同じ`FIELD_MAP`経由で
これを再利用、`resource_registry.rb:60-78`）に共有される、**既存の
唯一の意味論的中間表現**である。

### 2. 源の比較（実測）

**制約（プロンプト既定）**: JSON/FSHが独立にOPTから意味を導出する構造は
不可（二重導出禁止）。

- **(a) ファサードの中間表現を共有**: `FieldExtractor#entries`を
  そのまま新設`FshGenerator`の入力にする。`ProfileGenerator`と全く同じ
  契約（`entries[].{archetype_id, rm_type, concept, fields}`、
  `fields[].{name, rm_type, node_id, archetype_id, units, code_list,
  code_labels, terminology_id, required}`）を再利用でき、JSON/FSH間の
  二重導出リスクはゼロ。**推奨**
- **(b) pathcardsを源にする**: anlageの`Opt::PathcardExtractor`
  （`app/lib/opt/pathcard_extractor.rb`）は`FieldExtractor`とは独立した
  別のOPT walker（schema v1.1、`semantics`/`constraints`/`bindings`
  構造）。これを使うとJSON（gem・`FieldExtractor`経由）とFSH（anlage・
  `PathcardExtractor`経由）が別々にOPTから意味を導出する構造になり、
  二重導出禁止に抵触する。**却下**
- **(c) 新設写像層**: 新しい独立したOPT walkerを新設する案は(b)と同じ
  理由で却下。ただし「`FieldExtractor`の出力を消費する新しい変換層」
  （＝FSH文字列を組み立てる`FshGenerator`）は(a)の実装そのものであり、
  これは妥当

**bindings写像の実測比較（決定的な発見）**: `FieldExtractor#coded_text_constraints`
（`field_extractor.rb:191-203`）は`defining_code`直下の`code_list`
（ローカル列挙コード、例: ProblemListの`at0073`ローカルcode_list）のみを
抽出し、**`term_bindings`（外部語彙への`code_binding`）も
`C_CODE_REFERENCE.reference_set_uri`（値集合参照＝`value_set_binding`）
も一切抽出していない**。これは`ProfileGenerator#apply_value_constraints`
（`profile_generator.rb:125-129`）が`DV_CODED_TEXT`に対し
`binding: { strength: 'required' }`のみを出力し**`valueSet`キーを
含まない**という、既存JSONファサード自身の未解消のギャップと直結する
実測事実（FSH固有の問題ではない）。

この2種のbinding抽出は、anlageの`Opt::PathcardExtractor`
（`bindings_for`/`extract_code_bindings`、`pathcard_extractor.rb:243-280`）
に**既に実装されている**（`value_set_binding`は`C_CODE_REFERENCE#reference_set_uri`
から、`code_binding`は`//term_bindings/items`から）。実カードで実測:

- ProblemList `at0002`: `{"kind":"value_set_binding","system_uri":
  "terminology:http://id.who.int/icd/release/11/mms","code":null,
  "display":null}`（`spec/fixtures/pathcards/ProblemList.golden.json`実測）
- CardiologyEncounter `at0004`: `{"kind":"code_binding","system_uri":
  "SNOMED-CT","code":"[SNOMED-CT(2003)::271649006]","display":null}`
  （同、`CardiologyEncounter.golden.json`実測）。`at0005`は同型の
  `code_binding`だが実コードは golden fixture 側で`<REDACTED_SNOMED_CODE>`
  へ意図的に置換済み（下記「SNOMEDリテラル予算」参照）

**含意**: FSH出力（特にbindingの`from`節）を`FieldExtractor`のみから
組み立てると、既存JSONファサードと同じ「bindingが空」の欠落を継承する。
FSHの主要な価値（外部語彙bindingの明示）を実現するには、
**`FieldExtractor`自体に`value_set_binding`/`code_binding`抽出を追加する
gemレベルの拡張が前提**になる（`coded_text_constraints`の隣に、
anlageの`extract_code_bindings`と同型のロジックを実装として持ち込む形。
JSON側`ProfileGenerator`も同じ拡張の恩恵を受け、既存の`valueSet`欠落
バグが副次的に解消される）。これはFSH固有ではなくgem共通基盤の修正
であり、実装フェーズでは独立コミット（必要なら別Issue）として切り出す
べき判断材料。

### 3. v1サブセットの範囲確定

現行JSONファサードが表現している要素（`ProfileGenerator`実測）と、
FSH文法での対応形（Sushi実行で実測確認、下記）:

| JSON要素 | 実装箇所 | FSH対応形（Sushi実測で確認済み） |
|---|---|---|
| resourceType/id/url/name/title/status/fhirVersion/kind/type/baseDefinition/derivation | `build_profile`（`profile_generator.rb:33-50`） | `Profile:`/`Parent:`/`Id:`/`Title:`のメタデータ行（直接対応） |
| `code`要素へのarchetype_id `patternCodeableConcept`（`code_element`、行62-69） | 同上 | `* code.coding.system = ...`/`* code.coding.code = ...`または`patternCodeableConcept`相当の代入規則 |
| 単一leaf → `value[x]`のmin/type（`value_elements`、行71-80） | 同上 | `* value[x] 0..1`/`* value[x] only Quantity`等 |
| 複数leaf → `component`スライシング＋各slice（`component_elements`/`component_slice`、行82-113） | 同上 | `* component ^slicing...`＋`* component contains <slice> 0..1`＋`* component[<slice>].code = ...`（Sushi実測で確認、下記） |
| `DV_QUANTITY`の`patternQuantity`（unit、行117-124） | `apply_value_constraints` | `* value[x].unit = "..."` |
| `DV_CODED_TEXT`の`binding: {strength: required}`（valueSet欠落、行125-129） | 同上 | `* value[x] from <valueSet> (required)`（**valueSet自体は上記2節のgem拡張が前提**） |

**Sushi実測（実際にコンパイルして確認、`/tmp`スクラッチで実行、コミット無し）**:

1. `* code from http://id.who.int/icd/release/11/mms (required)`
   → `{"binding":{"strength":"required","valueSet":"http://id.who.int/
   icd/release/11/mms"}}`（value_set_binding型の写像を実証）
2. スライシング宣言（`^slicing.discriminator.type = #pattern`等）＋
   `* component contains systolic 0..1`＋`Alias: SCT = http://snomed.info/sct`
   ＋`* component[systolic].code = SCT#271649006 "..."`
   → `{"patternCodeableConcept":{"coding":[{"code":"271649006",
   "system":"http://snomed.info/sct","display":"..."}]}}`（code_binding型の
   写像を実証。gemの`component_slice`が生成する既存JSON構造と同一の
   `patternCodeableConcept`形状）

`magnitude_range`（`FieldExtractor#quantity_constraints`が抽出するが
`ProfileGenerator`は現状未使用、`field_extractor.rb:180-189`）はJSON側で
既に「抽出されているが出力されていない」既存ギャップであり、v1範囲には
含めない（JSON側の同ギャップ解消が先決、別判断）。

### 4. Sushi検証の分離設計

**Sushiは実在し、実際に動作することを実測確認済み**（`sushi --version`
→ `SUSHI v3.16.0`、`fsh-sushi@3.16.0`グローバルインストール、開発機の
nvm経由）。ただし**anlageリポジトリには現状Node/npmプロジェクトが
一切存在しない**（`package.json`無し、`.node-version`無し、CI
（`.github/workflows/ci.yml`）もNode setupを一切行わない——`scan_js`
ジョブの`bin/importmap audit`はRuby側のimportmap-rails機能で完結して
おりNode実行系を要さない）。Sushi導入は**新規のNode依存追加**という
インフラ判断を要する。

**ネットワーク依存の実測**: Sushi初回実行時、`hl7.terminology.r5`・
`hl7.fhir.uv.extensions.r5`・`hl7.fhir.r5.core`をpackages.fhir.orgから
ダウンロードし`~/.fhir/packages`にキャッシュする（実測、初回のみ数十秒）。
CI組み込みの場合、GitHub Actionsランナーからのネットワークアクセスに
依存する（`actions/cache`での`~/.fhir/packages`キャッシュが
`bin/rubocop`と同じパターンで有効、`ci.yml`の`lint`ジョブの
`actions/cache@v5`使用実績あり）。

**設計方針**: FSH生成は純Ruby（gem内`FshGenerator`、Sushiに依存しない）。
Sushi検証は別途の`rake fsh:verify`相当のタスクとして隔離し、Node/npm
セットアップの有無に関わらずFSH生成自体は動作する構成にする。CI組み込み
の要否（新規`fsh_lint`ジョブ追加等）は判断材料としてplanに提示し、
裁定はplan承認時に委ねる（evalハーネスと異なりSushiは合否判定器で
あるためCI適性は高いが、Node依存の新規追加という判断を要する）。

### 5. 出力の提供形（比較のみ、plan本体で選定）

- ダウンロードendpoint（例: `GET /fhir/profiles/:id.fsh`）
- `rake fsh:export`（既存`pathcards:eval`/`pathcards:backfill`と同型）
- ファサード隣接ルート（`profiles_controller`に`.fsh`フォーマット追加）

### SNOMEDリテラル予算（既存の実測発見、plan/TDD方針に直結）

`spec/fixtures/pathcards/CardiologyEncounter.golden.json`を実測した
結果、`at0004`は実SNOMEDコード`271649006`をそのまま保持する一方、
`at0005`（同種term_binding、元OPTには実コード`271650006`が存在——
`spec/fixtures/opt/CardiologyEncounter.opt:1043`実測）は
`<REDACTED_SNOMED_CODE>`という**意図的なプレースホルダへ置換済み**
であることを確認した。これは「golden fixtureへ複数の実SNOMEDコード
文字列を書き込まない」という既存の編集方針（WP5「terminologyモジュール」
節の防火壁条項——`claude-code-prompt_semantic-pathcards.md:101`
「施設・プロジェクトライセンス系コンテンツを扱う時点で別プロセスへ
昇格」と同根の慎重姿勢）の実例と解釈できる。FSHのgolden fixtureも
この予算内（新規の実コード文字列を増やさず、既存`at0004`/`271649006`
を再利用する）に収める方針を、Step 2計画のTDD節に明記する。

### Step 2への引き継ぎ

上記5点＋SNOMEDリテラル予算の発見を踏まえ、源の確定（(a)推奨）・
gem拡張の前提（binding抽出）・v1範囲・TDD（golden、SNOMED予算遵守）・
Sushi検証の位置づけ・出力形・コミット分割・承認事項を
`docs/design/fsh-plan.md`に起こす。
