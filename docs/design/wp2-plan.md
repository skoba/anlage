# WP2 実装計画: パスカード抽出器

**作成日**: 2026-08-23
**位置づけ**: `claude-code-prompt_semantic-pathcards.md` WP2 の実装計画。WP1成果物
`docs/design/pathcards-schema-v1.md`（2026-08-22条件付き承認）の承認条件C1/C2を
本計画で解決する。承認後、テストTODOリスト先頭のRedから実装に入る。
**前提文書**: pathcards-schema-v1.md（スキーマ・サンプルカード3枚）／
pathcards-language-policy.md（未翻訳2段階検出）／pathcards-wp0-exploration.md（API棚卸し）
**関連Issue**: skoba/anlage#6（WP2 goal・計画承認までのマイルストーン）／
skoba/anlage#8（WP2実装本体、TODO 1〜14のAcceptance criteria）／
skoba/anlage#7（canonicalデータ混在時のpath不一致、C1の留保事項）

---

## 1. 抽出器の設計

### 1.1 クラス構成（すべてAnlage内。層規律＝CLAUDE.md規律5に適合）

既存の `app/lib/opt/` サービスオブジェクト群（`Opt::TemplateDiff.call` / `Opt::FormValidator.call` の「クラスメソッド `.call` → インスタンス処理」慣行、`app/lib/opt/template_diff.rb:17,26`で確認済み）に合わせる。

| クラス | ファイル | 責務 |
|---|---|---|
| `Opt::PathcardExtractor` | `app/lib/opt/pathcard_extractor.rb` | 入口。`call(template)` → `Result(cards:, report:)`。definition木走査・カード組み立て・bindings統合 |
| `Opt::TermBindingExtractor`（term_bindings専用、内部で肥大したらPathcardExtractorから分離） | 同上 | source_xml再解析でterm_bindingsのみ取得（4節） |
| `Opt::SafeParser.safe_document`（既存クラスへのメソッド追加） | `app/lib/opt/safe_parser.rb` | DOCTYPE拒否後にNokogiri Documentを返す第2入口（4節） |

- **入力**: `Template`（`source_xml`を保持。`app/models/template.rb:22-39`）。抽出器内部で`Opt::SafeParser.parse`によりパース済み`OperationalTemplate`を取得し、term_bindingsのみ`safe_document`で別途取る。source_xmlの再パースはFHIRファサードに前例あり（`app/controllers/fhir/profiles_controller.rb:24-29`が毎リクエスト再パース）
- **出力**: `Result = Struct.new(:cards, :report)`。`cards`はスキーマv1準拠のHash配列（JSON化可能・string key）。`report`は言語ポリシー6節の抽出時レポート（未翻訳疑い一覧・スキップノード一覧）。DBに保存するのは`cards`のみ、`report`はログ出力（UI表出はWP3以降）

### 1.2 ノード走査

`Archetype#physical_paths`はパス文字列しか返さず、`each_constraint_node`はprivate（WP0 2.2節）。よって抽出器が自前で再帰走査する。走査中に保持する状態:

1. **path**: FieldExtractor実測形と同一の構文で構築する（`openehr-rails/lib/openehr_rails/opt/field_extractor.rb:129-135`と同じ「`/rm_attribute_name` ＋ node_idがあれば`[atNNNN]`」連結。トップレベルC_ARCHETYPE_ROOTは`content[<archetype_id>]`、埋め込みC_ARCHETYPE_ROOTは実node_id（例 at0000）——C1確定方針〔2節〕に従う）
2. **所属archetype_id**: 直近のC_ARCHETYPE_ROOTを降下時に更新（スキーマ設計判断4。upstream-candidates 7項の誤解決の再発防止をAnlage側で最初から設計に入れる）
3. **カード化単位**: `rm_type_name == "ELEMENT"`のCComplexObjectごとに1枚。path末尾は`/value`、`at_code`はELEMENTのnode_id、`rm_type`はvalue子制約の型（サンプルカード3枚と同形）

**FieldExtractorとの差分（意図的な上位集合）**: FieldExtractorは`DESCENDABLE_ATTRIBUTES = %w[data events items value]`に限定しprotocol/stateを降りない（`field_extractor.rb:43-44`）。抽出器は**全attributeを降下**し、protocol/state配下のELEMENTもカード化する。WP2 DoD「全ノードのカード化」の解釈をここに固定する（captureブロックが空のままなのは設計判断5どおり）。

### 1.3 ノード種別ごとの振る舞い（value子制約クラスでディスパッチ）

判定は`is_a?`で行い、**`CCodeReference`を`CCodePhrase`より先に判定**する（`class CCodeReference < CCodePhrase`、`openehr-2.3.1/lib/openehr/am/openehr_profile/data_types/text.rb:51`）。

| value制約クラス | constraints.value | bindings寄与 |
|---|---|---|
| `CDvQuantity` | property（CodePhrase→`{terminology, code}`）／list先頭の`CQuantityItem`から units・magnitude_range・precision_range（`xml_domain_type_parsing.rb:44-60`） | なし |
| `CCodeReference` | `{}`（カード1どおり。ローカルcode_listなし） | `value_set_binding`: system_uri=`reference_set_uri`（`xml_domain_type_parsing.rb:19-25`で正規パース済み）、code=null |
| `CCodePhrase`（DV_CODED_TEXT defining_code） | `code_list: [{code, label}]`。labelは**所属archetype**のcomponent_terminologyから引く（下記1.4節の安全なパターンで） | なし（外部参照が無いため） |
| その他（DV_TEXT・C_DATE系・CDvOrdinal等） | `{}`（v1スキーマにキー未定義） | なし。ordinal等はreportに「v1未対応制約」として記録（値の捏造・書き換えはしない） |

**constraints.occurrencesの定義（2026-08-23裁定）**: `constraints.occurrences`は**ELEMENT自身**のoccurrences。カードの単位はELEMENT（データ点）であり、identityが指すノードの制約を書くのが一貫性がある。ELEMENTのoccurrencesは親構造内での出現回数（臨床的な必須/任意/反復の意味を運ぶ）。`CDvQuantity`等value制約側のoccurrences（valueという単数属性の内部事情で情報量が乏しい）はv1では採らない（意図的非採用。必要が実証されたらv1.1で`constraints.value`配下への追加を検討する）。

edge case方針: CQuantityItemが複数（複数units）の場合はv1では先頭のみ採用しreportに記録（スキーマはunits単数。v1.1課題として残す）。occurrences欠損（WP0未確認事項3、`pathcards-wp0-exploration.md:770-772` — `numeric_interval`がnilを返し`CObject#occurrences=`が`ArgumentError`を投げる可能性が実データ未検証のまま記録されている）は、TODOリストで実データに対して実測し挙動を固定する。

**as-built（TODO 7実装時に判明）— DV_CODED_TEXTのvalue制約の実構造**: 上表の`CCodePhrase`/`CCodeReference`はELEMENTの`value`属性の子として**直接**現れるのではなく、`rm_type_name: DV_CODED_TEXT`の`C_COMPLEX_OBJECT`にラップされ、その`defining_code`属性（`C_SINGLE_ATTRIBUTE`）の子として現れる（実例: `spec/fixtures/opt/ProblemList.opt:563-575`、at0073の`value`属性→`children xsi:type="C_COMPLEX_OBJECT"`〔`rm_type_name: DV_CODED_TEXT`〕→`attributes xsi:type="C_SINGLE_ATTRIBUTE"`〔`rm_attribute_name: defining_code`〕→本体）。`CDvQuantity`はこのラップを持たず、value属性の直接の子として現れる（実例: 同ファイルat0004、`children xsi:type="C_DV_QUANTITY"`が`value`属性の直下）。抽出器はこの差を`defining_code_constraint`ヘルパー（value_constraintを受け取り、`rm_type_name == "DV_CODED_TEXT"`ならdefining_code配下の実体を返し、それ以外はそのまま返す）で吸収し、`CCodePhrase`/`CCodeReference`両方の判定前に必ずこのヘルパーを通す設計にした（`app/lib/opt/pathcard_extractor.rb`）。

**as-built（WP3 C1実装時に発見・2026-08-24裁定で統一）— value属性が複数の代替RM型を持つ場合の解決規約**: `value`属性は`C_SINGLE_ATTRIBUTE`の子として複数の代替RM型を持ちうる（実例: `ProblemList.opt`のat0002、`DV_TEXT`〔290行〕と`DV_CODED_TEXT`〔302行〕の2代替。自由記述またはコード化診断名のいずれも許容するOR制約）。WP2実装時点ではこのケースが未検出だったため、`constraints_for`は`value_attribute.children.first`（XML出現順で最初の代替）を無条件に採用する一方、`bindings_for`は`value_attribute.children`全体を走査し外部コード参照（`CCodeReference`）を持つ代替を優先的に探すという、**異なる規約が同居**していた（前者はat0002でDV_TEXTを、後者はDV_CODED_TEXTの束縛を見る、という食い違いを許す設計だった）。WP3でパスカードに`semantics.rm_type`を追加した際、この食い違いが「同一ノードなのにrm_type（第三の値）と実際に使われているbindings/constraintsの解釈が一致しない」という形で顕在化した。

v1.1裁定（2026-08-24、`docs/design/pathcards-schema-v1.md`設計判断9）により、以下へ統一する:
- 共有ヘルパー（`primary_value_alternative`相当）を新設し、`rm_type_for`・`constraints_for`・`bindings_for`の3関数が同一ノードで必ず同じ代替を見る、という不変条件を導入する
- 主型選定規約: 外部コード参照（`CCodeReference`）を持つ代替があればそれを優先、無ければXML出現順で最初の代替を採用する（`DV_CODED_TEXT` > `DV_TEXT`という優先はこの規約の具体例）
- `constraints.value_alternatives`（value制約側の複数代替対応）はv1.1では追加しない（YAGNI。実需が出た時点でv1.2で検討）

### 1.4 labels / descriptions / 未翻訳検出

**実装上の制約（WP0未確認事項2への対応）**: labelsとdescriptionsの取得は、`FieldExtractor#term_text`（`field_extractor.rb:258-267`）と同じ「`component_terminologies[archetype_id].term_definitions.each_value { |terms| terms.find { |t| t.code == code } }`」パターンを踏襲する。`ArchetypeOntology#term_definition(lang:, code:)`（`openehr/am/archetype/ontology.rb:70-76`）は**使わない** — この方法は`@term_definitions[lang][code]`という2段Hash索引を前提とするが、OPTParserが構築する`term_definitions`の値は`ArchetypeTerm`の配列であり（`opt_parser.rb:159-168`）、`Array#[](String)`となって`TypeError`になる可能性がWP0で指摘済み・実データ未検証のまま残っている（`pathcards-wp0-exploration.md:764-769`）。実績のある`each_value.find`パターンのみを使うことで、この未検証リスクを踏まない。

term_definitionsの`items`Hash（`'text'`/`'description'`キー）から text/description を取り、言語ポリシー4節の2段階検出をそのまま実装する:

- 段階1: `/\A\*(.+?)(?:\(([a-z]{2}(?:-[a-z]{2})?)\))?\z/i` → `fallback_marker`（`*Any event(en)`・`*Bloeddruk`・`*Appended (en)`の3変種すべて実観察済み）
- 段階2: `/[\p{Hiragana}\p{Katakana}\p{Han}]/` 不在 → `no_ja_script`

### 1.5 provenance

`source_checksum`は`Digest::SHA256.hexdigest(source_xml)`（`template.rb:33`と同一計算）、`extracted_at`は`Time.current.iso8601`、`extractor_version`は定数`Opt::PathcardExtractor::VERSION`（初期値`"wp2-0.1.0"`）。

### 1.6 カード保存先

**`templates`テーブルへの`pathcards` JSONカラム追加**（migration 1本）を採用する。

- 根拠: `web_template`等でJSONカラムの使用実績あり（`db/schema.rb:173`、他5箇所）。カードがtemplate行と同一ライフサイクルを持つため、supersede時（`templates_controller.rb:74` `superseding&.supersede!`）に旧版カードが**行ごとsuperseded化**され、追加のカード状態管理が不要。checksum一致の再ドロップは save前に早期リターンする（同:64-66）ためカードは行に残存し再抽出不要
- 代替案（独立`pathcards`テーブル）はWP3の索引設計（pgvector/PostgreSQL移行判断がWP3計画に留保。WP0 5節-1）と同時に再検討する。WP2でのテーブル正規化はスコープ規律（規律8）上見送る

---

## 2. C1（path正準形）の確定方針: (a) 実測形を正とする

2026-08-22の実測（Step 1）に基づき確定する:

- 埋め込みC_ARCHETYPE_ROOT（`LabResultReport.opt:492`のlaboratory_test_analyte.v1、node_id=at0000）のパスは実測形`items[at0000]`のまま採用する
- openehr-ruby AQLパーサは at-code述語形式・archetype述語形式の両方を文法上受理し（`lib/openehr/aql/parser.rb:167-190`、NodePredicate / ArchetypePredicate）、実行時マッチングはarchetype_node_idとの**完全文字列一致**のみ。openehr-rails側はFieldExtractorがパスに`child.node_id`を使い（`field_extractor.rb:134-135`）、Storableも RMグラフ格納時にarchetype_node_idへat0000をそのまま設定する（`storable.rb:188`）ため、**Anlage/Storable経路で保存されたデータには実測形パスがそのままAQL一致する**（実測確認済み）
- **留保＝別課題として切り出し**: canonical openEHR準拠データ（埋め込みルートのarchetype_node_idにarchetype_idを持つ外部由来JSON）には`items[at0000]`が0件になる（実測確認済み）。対応:
  1. **Anlage側にGitHub Issueを起票済み**（CLAUDE.md「Issue-driven visibility」(b)課題）: [skoba/anlage#7](https://github.com/skoba/anlage/issues/7)「canonicalデータ混在時の埋め込みルートパス不一致 — graph_builder経路での正規化変換の要否」。WP2実装Issue（#8）から`Refs`で相互参照
  2. **`docs/upstream-candidates.md`へ観察を追記**（追記のみ・規律5）: Storableが埋め込みC_ARCHETYPE_ROOTのarchetype_node_idにnode_id（at0000）を設定する挙動とcanonical仕様の食い違い
- schema文書1節のpath定義への追記（「pathはFieldExtractor実測形を正準とする」）は、本計画承認後の実装コミット列にdocs更新として含める

---

## 3. C2（コンテンツ防火壁）: golden snapshotの運用ルール

規律6の適用として以下を固定する:

1. **リテラルコードの上限**: golden期待値ファイルに書いてよいライセンス用語コード（SNOMED CT）は**全goldenで合計2件まで**。CardiologyEncounterのat0004（`[SNOMED-CT(2003)::271649006]`、fixture 1029-1035行、カード3既出）を唯一の必須リテラルとし、他のterm_bindingsはリテラルを書かず形状アサートに回す
2. **残りは形状アサート**: リテラルを書かないbindingsは「件数・kind・system_uri」のみ検証する（例: CardiologyEncounterのterm_bindings 2件、いずれもkind=code_binding, system_uri=SNOMED-CT）。code値はワイルドカード扱い
3. **value_set_bindingのURIはリテラル可**: `terminology:http://id.who.int/icd/release/11/mms`（`ProblemList.opt:334`）は値集合の**URI参照であり特定コードを含まない**ため防火壁の対象外と整理する
4. **出所明記の方式**: golden期待値は`spec/fixtures/pathcards/<TemplateId>.golden.json`に置き、(i) ファイル冒頭コメント（またはJSON内`_provenance`キー）に「抽出元fixtureファイル名・SHA-256（schema文書2節の表と同値）・CKM公開束縛由来である旨」を記載、(ii) リテラルコード1件ごとにfixture file:lineを併記、(iii) spec側describe文にも出所を書く
5. **golden対象OPT群の確定**（承認事項）: 現行3 fixture（CardiologyEncounter / LabResultReport / ProblemList、SHA-256はschema文書2節で固定済み）。ProblemListがreferenceSetUri経路（ICD 1件）、CardiologyEncounterがterm_bindings経路（SNOMED 9出現・bindings 2件）の代表となることを実測確認済み

---

## 4. 抽出二経路の実装方針

openehr 2.3.1 bump（C3解消、`e1bc037`）により再解析の必要範囲が縮小した。二経路を明確に分離する:

| 経路 | 取得対象 | 根拠 |
|---|---|---|
| **経路1: パース済み構造**（`Opt::SafeParser.parse` → definition木走査） | identity / semantics / constraints / **reference_set_uri**（value_set_binding） | `C_CODE_REFERENCE`は`CCodeReference`（`reference_set_uri`保持）として正規パースされる（`xml_domain_type_parsing.rb:19-25`、`text.rb:51-57`） |
| **経路2: source_xml再解析**（Nokogiri直接） | **term_bindingsのみ**（code_binding） | gemパーサはterm_bindingsを読まない（opt_parser.rb全文にterm_bindings非出現。openehr-ruby#31未解消。upstream-candidates 6項(b)） |

経路2の安全化（プロンプトWP2の明文要件「source_xml再解析もsafe_parser経由」）:

- `Opt::SafeParser`に`safe_document(source_xml)`を追加する。既存の`DOCTYPE_PATTERN`拒否（`safe_parser.rb:12-17`）を通した上で、`Nokogiri::XML::Document.parse`に**明示的ParseOptions（NONET有効・NOENT無効）**を渡してDocumentを返す。既存`parse`の挙動は変更しない（既存spec緑を維持）
- backlog項目1（UTF-16でDOCTYPE検知素通り）は**本WPのスコープ外のまま**とする。新経路のNONET明示化は backlog記載の(c)案を先取りする形になる——この点をbacklog項目1に追記する
- term_bindingsの所属スコープ解決: `//term_bindings`各要素から祖先軸で直近の`archetype_id/value`を持つ要素（C_ARCHETYPE_ROOT）を引き、`{archetype_id => {at_code => [{terminology, code_string}]}}`を構築。カード組み立て時にidentity（archetype_id, at_code）でマージする
- **code_stringの分解**（schema文書3節-3の持ち越し）: v1では**原文のまま保持**（カード3のgolden `"[SNOMED-CT(2003)::271649006]"`と一致させる）。`{system, version, code}`への分解はWP5（$lookup境界）の入力正規化として先送りする——承認事項に含める

---

## 5. TDD手順（t-wada方式）とテストTODOリスト

方針: プロンプトWP2の指示どおり「ノード種別ごとの振る舞いをユニットスペックで先に定義し、golden snapshotは最後の回帰網」とする。ただしユニットスペックの**期待値そのものにwp1-manualサンプルカード3枚の実値を使う**ことで、最初のred→greenサイクルから3枚の再現に向かって進む（実物主義）。golden比較時は`provenance.extracted_at` / `extractor_version`を正規化して除外する。

**カード1のpath差異の扱い**: カード1のpathは手作業導出でFieldExtractor実測未更新（schema文書3節-1）。抽出器の実測パスが手作業導出と食い違った場合は、**実測値を正としてschema文書2節を更新**する（人間確認の上。実物主義の適用——承認事項7）。

テストTODOリスト（`spec/lib/opt/pathcard_extractor_spec.rb`ほか。上から順に消化）:

1. **[shape]** `Opt::PathcardExtractor.call(template)`がカード配列を返し、各カードが`schema_version: "1.0"`と7ブロック（identity/semantics/constraints/bindings/capture/reserved/provenance）を持つ（CardiologyEncounter fixture）
2. **[identity]** カード3のidentity 4つ組（CardiologyEncounter / blood_pressure.v2 / `/content[...]/data[at0001]/events[at0006]/data[at0003]/items[at0004]/value` / at0004）を再現する
3. **[identity/scope]** 埋め込みC_ARCHETYPE_ROOT配下（LabResultReport at0001）で、archetype_idが宿主でなく`CLUSTER.laboratory_test_analyte.v1`、pathが`items[at0000]`経由になる（カード2。C1実測形の固定）
4. **[labels]** カード3のlabel「収縮期」（ja・untranslated_suspect: false）と、カード2のdescription`*The value of the analyte result. (en)`（fallback_marker・source_lang: en）を、1.4節の`each_value.find`パターンで再現する
5. **[labels]** マーカー無し未翻訳（ProblemListの原語残存ノード）で`no_ja_script`を検出し、日本語ラベル（「プロブレム・診断名」等）ではfalseになる
6. **[constraints/DV_QUANTITY]** カード3のproperty（openehr::125）・units（mm[Hg]）・magnitude_range（0.0≦x<1000.0）・precision_range（0..0）を再現する。occurrences欠損ノードの挙動もここで実測・固定（WP0未確認事項3）
7. **[constraints/DV_CODED_TEXT]** ローカルat-code値集合を持つ実ノード（ProblemList内から実測選定）で`code_list: [{code, label}]`を抽出する
8. **[bindings/value_set]** カード1のbindings（kind: value_set_binding、system_uri: `terminology:http://id.who.int/icd/release/11/mms`、code: null）を経路1（CCodeReference）から再現する
9. **[safe_document]** `Opt::SafeParser.safe_document`がDOCTYPE入力で`Opt::UnsafeTemplate`を投げ、正常OPTでNokogiri Documentを返す（`spec/lib/opt/safe_parser_spec.rb`新設）
10. **[bindings/code_binding]** カード3のbindings（kind: code_binding、system_uri: SNOMED-CT、code: 原文code_string）をsource_xml再解析（経路2）から再現し、所属archetypeスコープが正しい（C2ルール内の唯一のリテラルコード）
11. **[統合golden・3枚]** サンプルカード3枚の全フィールド一致（volatile provenance除外・C2ルール適用）。カード1のpath実測差異が出たらここで確定させる
12. **[hook]** POST /templates成功時に`template.pathcards`が保存される／previewでは抽出されない／checksum重複再ドロップで再抽出されない／supersede時に新版行へ新カードが入る（`spec/requests/templates_spec.rb`追記）
13. **[report]** 未翻訳疑いノード一覧（archetype_id・at_code・text・evidence）がResult.reportに載る（言語ポリシー6節）
14. **[golden回帰網・最後]** 3 fixtureの全ノードsnapshot（`spec/fixtures/pathcards/*.golden.json`、C2ルール適用）。DoD「全ノードのカード化が通る・日本語ラベル取得（未翻訳疑いは報告）」をここで束ねる

---

## 6. フック位置: 候補A（controller同期呼び出し）を推奨

- 位置: `TemplatesController#create`の`template.save`成功直後（`templates_controller.rb:73-74`、`superseding&.supersede!`の後）で`Opt::PathcardExtractor`を呼び、`template.pathcards`に代入する（save前に代入して1 INSERTにまとめる実装をGreenで選択可能——pathcardsの算出にDB採番されたidは不要なため）
- 候補B（`after_create`）を退ける理由: 既存specで`build_from_opt_xml`が11ファイル25箇所使用されており（うち`.save!`直結は5箇所）、コールバック化するとテスト全体で抽出器発火の影響範囲が広がる。また「OPT投入イベント」の意味論はテンプレート**登録**（ドロップゾーン経由）であり、モデル永続化一般ではない
- 同期/非同期: WP2は**同期**。ActiveJob基盤（`app/jobs/application_job.rb`、`Gemfile:28` solid_queue）はproductionのみqueue_adapter設定済みでdevelopment/testは未設定。デモ規模のOPTで抽出は軽量であり、非同期化（perform_later）は必要が実証されてから
- **失敗時はfail-soft**: 抽出例外で登録自体を失敗させない。`rescue StandardError`でログ（`Rails.logger.warn`）＋`pathcards`はnullのまま登録成功。この挙動もspecで固定する

---

## 7. Issue #3（patient_blood_pressure.opt復元）との依存関係

- **ブロックされない**: TODOリスト1〜13の全ユニット/統合サイクルと、3 fixture分のgolden回帰網（TODO 14）。WP2の新規specは現行3 fixtureのみを参照する
- **ブロックされる（制約を受ける）**:
  1. 全suite一括緑化（8スペックファイル・36 failuresが参照切れ、skoba/anlage#3）。→ WP2実装Issue（[#8](https://github.com/skoba/anlage/issues/8)）のAcceptance criteriaは「**WP2で追加・変更したspecのパス指定実行が緑**」と定義し、全suite緑は#3クローズ後の別条件とする
  2. patient_blood_pressure.optを**追加golden**（term_bindings 4件・SNOMED 17出現の実測済み素材）として取り込む拡張。→ #3解消後の任意フォローアップとし、C2の件数上限を再承認しない限りリテラルコードは追加しない。同OPTはreferenceSetUri/ICD系を含まない（実測0件）ため、golden対象3点の代表性は#3と無関係に成立している
- カード2の単位・値域入りOPT更新（AD作業・人間依頼中、schema文書4節-3で承認済みの差し替え運用）も非ブロッカー: 到着後に検収（言語ポリシー5節）→カード2 golden更新、の追加サイクルを積む

---

## 8. コミット分割案（1コミット＝1サイクル、テスト先行。Codex実装指示の粒度）

各コミットはRed（失敗確認）→Green→（必要ならRefactor）を含み、テストを伴わない実装コミットは作らない。`Refs #8`を付す。

1. `spec: PathcardExtractor returns schema-v1 shaped cards (red)` → `feat: minimal Opt::PathcardExtractor returning card skeletons`（TODO 1）
2. `feat: identity block via self-walked definition tree with archetype-root scoping`（TODO 2＋3。walker実装の本体。Refactorでwalkerをprivate整理）
3. `feat: labels/descriptions with 2-stage untranslated detection (each_value.find pattern)`（TODO 4＋5）
4. `feat: DV_QUANTITY constraints (property/units/magnitude/precision)`（TODO 6）
5. `feat: DV_CODED_TEXT local code_list + occurrences edge pin`（TODO 7）
6. `feat: value_set_binding from parsed CCodeReference`（TODO 8）
7. `feat: Opt::SafeParser.safe_document (DOCTYPE-gated Nokogiri entrypoint)`（TODO 9。既存parse挙動不変をspecで担保）
8. `feat: code_binding via term_bindings re-parse merged into cards`（TODO 10）
9. `test: full-card equality against wp1-manual sample cards`（TODO 11。カード1 path実測差異があればschema文書2節更新を同コミットに含め、コミットメッセージで人間確認済みを明記）
10. `feat: pathcards column + registration hook in TemplatesController#create`（TODO 12。migration＋request spec＋fail-soft pin）
11. `feat: extraction report (untranslated suspects)`（TODO 13）
12. `test: golden snapshot regression net for 3 fixtures`（TODO 14。C2ルール適用のgoldenファイル追加）
13. `docs: C1正準形のschema追記・upstream-candidates追記（Storable観察）・backlog項目1への注記`（docsのみ。Issue不要の範囲）

---

## 9. 承認が必要な判断（schema文書4節の型）

1. **本WP2計画全体**（クラス構成・保存先`templates.pathcards` JSONカラム・テストTODOリスト・コミット分割）
2. **C1確定**: 実測形(a)採用。canonical混在リスクのAnlage Issue起票＋upstream-candidates追記
3. **C2運用ルール**: リテラルSNOMEDコードは全goldenで合計2件以内（実際はat0004の1件）・出所記載方式・**golden対象OPT群を現行3 fixture（SHA-256固定）で確定**
4. **フック位置**: 候補A（controller同期・fail-soft）。候補B（after_create）は既存specへの広範な影響を理由に不採用
5. **code_string原文保持**: `[SNOMED-CT(2003)::271649006]`の分解はWP5境界へ先送り
6. **DoD「全ノード」の解釈**: ELEMENTデータ点単位・protocol/state配下も含む（FieldExtractorの上位集合）
7. **カード1 path差し替え運用**: 抽出器実測がwp1-manual手作業導出と食い違った場合、実測値を正としてschema文書2節を更新する
8. **Issue起票**: **完了**。(a) canonical混在Issue → [#7](https://github.com/skoba/anlage/issues/7) (b) WP2実装Issue → [#8](https://github.com/skoba/anlage/issues/8)（Acceptance criteria: 本計画TODO 1〜14のspec緑＋デモ経路通過。#3・#7と相互参照）

---

## 10. 完了記録（2026-08-23）

- **完了日**: 2026-08-23
- **最終SHA**: `1f1c802`（origin/main。進行ログ: `docs/reports/wp2-log.md` R1〜R8）
- **実測サマリ**: `bundle exec rspec` 79 examples, 0 failures（全suite一括、#3解消後）／`bundle exec rubocop`（実装＋spec関連14ファイル）オフェンスなし／golden回帰網3本（CardiologyEncounter 2カード・LabResultReport 3カード・ProblemList 6カード、C2ルール適用）／TODOリスト14/14完了
- **[skoba/anlage#8](https://github.com/skoba/anlage/issues/8)**: CLOSED（Fixes #8）。**[#6](https://github.com/skoba/anlage/issues/6)**（旧マイルストーン）も#8への引き継ぎを明記の上CLOSED
- **WP0未確認事項の消化状況**:
  - 事項2（`ArchetypeOntology#term_definition`のTypeErrorリスク、`pathcards-wp0-exploration.md:764-769`）: **計画で回避**。実装は`FieldExtractor#term_text`と同じ`each_value.find`パターンを採用し、リスクのあるメソッドを一切呼ばない（本文書1.4節）
  - 事項3（occurrences欠損時の挙動、`pathcards-wp0-exploration.md:770-772`）: **R系列③（R3、TODO 6）で実データ固定**。LabResultReport at0001の`upper_unbounded`ケースで実測し、例外を投げず`upper: null`になることを確認（`pathcards-schema-v1.md` カード2）
  - `pathcards-schema-v1.md` 3節-1（ProblemList.optのAnlage実行時動作・登録/保存動作が未確認だった件）: **TODO 12で消化**。実際にドロップゾーンへ投入し登録・`pathcards`保存まで実演済み（`docs/evidence/2026-08-23--problemlist--pathcards-saved-after-wp2-todo12.png`）
