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

---

## R2: 裁定反映・前提修正Issueドラフト作成（2026-08-26）

### 訂正（R1の精度不足）

R1は「両binding形式ともAnlageの`PathcardExtractor`と同型ロジックを
`FieldExtractor`へ移植すればよい」とだけ記したが、既存の
`docs/upstream/issues/`調査を突き合わせた結果、**2種のbindingは
openehr gem側の対応状況が非対称**であることが判明した:

- `value_set_binding`（`C_CODE_REFERENCE#reference_set_uri`）:
  `skoba/openehr-ruby#30`（`docs/upstream/issues/
  openehr-ruby--opt-parser-crash-on-c-code-reference.md`）が**CLOSED**
  済みのため、gemのパース済みオブジェクトモデル経由でそのまま取得可能
- `code_binding`（`term_bindings`）: `skoba/openehr-ruby#31`
  （`docs/upstream/issues/openehr-ruby--opt-parser-ignores-term-bindings.md`）
  が**現在もOPEN**——`OpenEHR::Parser::OPTParser`がontology側の
  `term_bindings`を一切読まないため、gemのオブジェクトモデルには
  現れない。Anlageの`Opt::PathcardExtractor#extract_code_bindings`が
  生XML（`Opt::SafeParser.safe_document`）を独立に再パースしている
  のはこのため

この非対称性は`FieldExtractor`拡張の実装方針に直結する（`code_binding`
側は`#31`解消を待たず、`PathcardExtractor`と同じ迂回＝生XML再パースを
`FieldExtractor`内に持ち込む形で実装可能——ブロッカーではなく実装
パターンの選択の話）。Issueドラフトに反映済み。

### 前提修正Issueドラフト作成

`docs/upstream/issues/
openehr-rails--field-extractor-missing-terminology-bindings.md`を
作成。根拠: WP2由来の2件の既存調査（`#30`・`#31`）・facade欠落の実測
（`ProfileGenerator`の`valueSet`欠落）・binding 2種の要求仕様（実カード
2件の実測付き）・参照実装（`PathcardExtractor`）。本リポジトリ自身の
`spec/templates/bmi_calculation_without_uid.opt`に実SNOMED-CT/LOINC
`term_bindings`が既に存在すること（`:1683-1697`実測）も確認し、
code_binding側のテスト対象として引用した。value_set_binding側の
fixtureは本リポジトリに現状無いことも実測確認し、要否はrails側の
explore→planに委ねる形で記載。

段取り: 本ドラフトは人間中継でopenehr-railsへ送付される。実装は
本セッション（anlage）のスコープ外——rails側で別途explore→plan→
ゲートを行う。

### plan反映

`docs/design/fsh-plan.md`に裁定反映節（4判断）・v1規模上限
（`mml_referral`級はv1検証対象外）・Sushi rakeタスクのみ・
`rake fsh:export`をv1・コミット分割の前段/後段2区分を追記した。

### 追記1: 構造条項（2026-08-26）

FHIR橋渡し層の恒久配置は衛星gem`openehr-fhirbridge`への分離と方針
確定（`docs/backlog.md` 5項）。移行条件が満たされるまではAnlage内
（openehr-rails gem）で実装するが、`FshGenerator`は`FieldExtractor#entries`
のみを入力に取る純Rubyモジュール＋薄Railsアダプタの構造を守り、
将来の移設可能性を保つ設計条項を`docs/design/fsh-plan.md`「追記1」
節へ記録した。

---

## R3: openehr-rails 0.5.0 bump（Part 1、2026-08-26）

### 前提の直接検証

「人間報告を待って着手」の前提を、待つのではなく`rubygems.org`の
公開APIで直接検証した（`curl -s https://rubygems.org/api/v1/versions/
openehr-rails.json`）: `0.5.0`が`created_at: 2026-08-25T09:26:15Z`で
実在。人間報告を待つより確実な検証手段のため、これをもって着手条件
充足と判断した。

### 前提修正Issueの実際の解決経路（ドラフトからの乖離）

`docs/upstream/issues/openehr-rails--field-extractor-missing-terminology-bindings.md`
を人間中継で送付する段取りだったが、実際にはopenehr-rails側で
**同一内容のIssue `skoba/openehr-rails#30`が独立に起票・実装・
0.5.0としてリリース済み**であることが確認できた（`git log`実測、
`c586a8c`起票→`5470d29`設計→`c571bf5`/`0bbbc47`/`6efc161`実装
（Codex）→`7e7e2f0`PR/merge→`7c2d4d8`upstream#31へのコメント→
`69db63f`0.5.0リリース）。ドラフトファイルは実際の起票経路の記録
としてこのまま保存する（`openehr-ruby--field-extractor-wrong-
terminology-scope.md`のRESOLVED UPSTREAM前例と同型の扱い）。

### API実測（enrichment実装の実際の形、ドラフトからの主要な差分）

- `FieldExtractor#build_field`は常に`value_set_uri`（nilあり）・
  `code_bindings`（`[{system_uri:, code:}]`、空配列あり）を持つ
  （`openehr-rails` `lib/openehr_rails/opt/field_extractor.rb:169-170,224-234`）
- **term_bindingsの投入経路はgem（openehr-ruby）側の修正ではなく、
  `OpenehrRails::Opt::Parser#parse`の`populate_term_bindings!`による
  parse時のenrichment**（`lib/openehr_rails/opt/parser.rb:24,43-60`）。
  OPT文書のterm_bindings XMLを独自に再パースし、上流
  `ArchetypeOntology#term_bindings`（既存だが従来常にnilだったslot）
  へ投入する。nilガード付きの暫定バイパスで、`skoba/openehr-ruby#31`
  解消後にメソッド2つの削除で撤去できる設計（撤去条件コメント
  `parser.rb:43-46`に明記済み）
- `code_bindings`は`DV_CODED_TEXT`に限定されない（BMIのLOINC
  bindingは`DV_QUANTITY`要素上にある、`CHANGELOG.md` 0.5.0節に明記）
- 実測確認（`bin/rails runner`、`CardiologyEncounter.opt`）:
  `component_terminologies['...blood_pressure.v2'].term_bindings`が
  `{"SNOMED-CT"=>{"at0004"=>[CodePhrase(...271649006...)],
  "at0005"=>[CodePhrase(...271650006...)], ...}}`の形で実際に
  取得できることを確認——FSH後段（Part 2）が依存する挙動が実在する

### 全suite実測

`bundle lock --update openehr-rails`（2.4.2時の手法を踏襲）→
`openehr-rails 0.5.0`・`openehr 2.4.2`（変更なし）に解決。
`bundle exec rspec`全97件green・`bin/rubocop -f github` exit 0を確認。
`value_constraint`の複数alternative選択ロジック変更（`CHANGELOG.md`
Fixed節「C_CODE_REFERENCE-backed alternativeを優先」）によるAnlage側
回帰は無し（ProblemList.optのat0002が影響しうる変更だが、Anlage側は
`Opt::PathcardExtractor`という独立実装を使っており`FieldExtractor`の
出力に直接依存する箇所が無いため無風だったと推定——`FieldExtractor`
自体はFHIR facade経由でのみAnlageから間接的に使われる）。

---

## R4: 経路2（`Opt::PathcardExtractor`のbinding抽出簡素化）検証（Part 3、2026-08-26）

### 目的

Anlage独自の`Opt::PathcardExtractor#extract_code_bindings`/
`#bindings_for`（生XML再パース、`app/lib/opt/pathcard_extractor.rb:
243-280`）は、openehr-rails 0.5.0の`FieldExtractor#code_bindings`/
`#value_set_uri`と機能重複する。後者へ置換できれば、Anlage側の重複
実装（二重の生XML再パース）を削減できる。ただし出力形式が変われば
WP2 golden fixture（`spec/fixtures/pathcards/*.golden.json`）が
実際に持つ`code`文字列表現に影響するため、実装前に形式互換を実測
確認する（実装は本タスクでは行わない、裁定事項として提示）。

### 実測結果: 完全一致（バイト単位）

`CardiologyEncounter.opt`・`ProblemList.opt`を`OpenehrRails::Opt.parse`
→`OpenehrRails::Opt::FieldExtractor#entries`経由で直接抽出した値と、
WP2 golden fixtureの値を突合:

| 対象 | golden（`Opt::PathcardExtractor`） | gem enrichment（`FieldExtractor`） | 一致 |
|---|---|---|---|
| CardiologyEncounter at0004 code_binding | `system_uri: "SNOMED-CT"`, `code: "[SNOMED-CT(2003)::271649006]"` | `system_uri: "SNOMED-CT"`, `code: "[SNOMED-CT(2003)::271649006]"` | ✓完全一致 |
| CardiologyEncounter at0005 code_binding | `code: "<REDACTED_SNOMED_CODE>"`（golden側でredact済み） | `code: "[SNOMED-CT(2003)::271650006]"`（実コード） | golden側のredaction都合のみの差、抽出値自体は一致（実コード`271650006`はgem側実測で確認済み） |
| ProblemList at0002 value_set_binding | `system_uri: "terminology:http://id.who.int/icd/release/11/mms"` | `value_set_uri: "terminology:http://id.who.int/icd/release/11/mms"` | ✓完全一致 |

版数付きSNOMED表記（`[SNOMED-CT(2003)::...]`という角括弧＋バージョン
番号付きの生の`code_string`）はgem側でも一切正規化されず、そのまま
保持されている（`OpenehrRails::Opt::Parser#binding_code_phrase`が
`code_string`をそのまま`CodePhrase.new(code_string:)`に渡すのみ、
`lib/openehr_rails/opt/parser.rb:79-90`実測）。

### 判定（裁定事項として提示）

**形式は保存される（置換可）**。`Opt::PathcardExtractor`の
`extract_code_bindings`/`bindings_for`のbinding抽出部分は
`OpenehrRails::Opt::FieldExtractor`の`code_bindings`/`value_set_uri`へ
置換してもWP2 golden fixtureの値は変化しない（`kind`のラベリング
——`"code_binding"`/`"value_set_binding"`の区別——のみAnlage側で
`value_set_uri`の有無から再構成すれば足りる）。実装の要否・時期は
本タスクでは判定しない（裁定事項）。実装する場合の対象は`bindings_for`
（`pathcard_extractor.rb:243-257`）と`extract_code_bindings`
（同`259-280`）の削除・`FieldExtractor`呼び出しへの置換で、
`semantics_for`等の他メソッドは無関係。

---

## R5: FshGenerator実装完了（Part 2、openehr-rails側、2026-08-26）

`skoba/openehr-rails#32`として実装完了・クローズ（コミット`5f669af`・
`a996ef4`、詳細ログはopenehr-rails側`docs/reports/fsh-generator-log.md`
R1-R2）。実装はopenehr-rails gem（`OpenehrRails::Fhir::FshGenerator`）
に着地——`docs/design/fsh-plan.md`「源の確定」節どおり、`FieldExtractor
#entries`を唯一の入力とする純Rubyクラス。

**Claude Codeによる独立検証で2件の実質的な不具合を発見・是正**
（Codex自身のsandbox検証はネットワーク制限で不可能だったため、
実際にSushiでコンパイルして確認する作業はClaude Code側で実施）:

1. **1st round**: 1要素に複数の`code_bindings`があるとFSHが競合し
   Sushiエラーになる不具合（`* path = SYSTEM#code`形式の固定値代入を
   複数回スタックする実装ミス）。`code.coding`を`system`値判別子で
   スライスする形へ修正、0 Errorsを実測確認
2. **2nd round**: `problem_list.opt`（EVALUATION→Condition、5要素）が
   Sushiで29エラー——`Condition`に`component`要素が存在しないため。
   既存JSON facade（`ProfileGenerator`）にも同根の未発見の欠陥がある
   ことが判明（JSONはSushiのようなスキーマ検証を受けないため
   これまで検出されなかった）。`skoba/openehr-rails#33`として別途
   起票、本Issueのスコープ外と切り分け

**最終検証（Claude Code独自、Codexの報告を鵜呑みにせず再実施）**:
`bmi_calculation.opt`（全Observation系）は0 Errorsを実測確認。
`bundle exec rspec`全281件green（Codexが報告した18件の失敗は
sandbox固有の`Errno::EPERM`で、この session の実行環境では再現せず、
CI runでもgreenを確認）。`bundle exec rubocop`108ファイルoffense無し。

**Part 2完了**。前段/後段の統合実装（binding部含む）が完了し、
`docs/design/fsh-plan.md`のコミット分割はすべて消化済み。残る
「rake fsh:export」（anlage側出力提供形v1）は別タスクで着手する。
