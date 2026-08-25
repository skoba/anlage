# FSHエクスポート 実装計画（explore→plan、実装しない）

**作成日**: 2026-08-26
**対象Issue**: `skoba/anlage#17`（goal）
**位置づけ**: openEHRテンプレート→FHIR profile生成の出力にFSH（FHIR
Shorthand）を追加する。WP0-5本流ではなく、既存FHIR facade（`skoba/
anlage`の`Fhir::ProfilesController`、gem`openehr-rails`の
`OpenehrRails::Fhir::ProfileGenerator`）に対する新規機能。
**ログ**: `docs/reports/fsh-log.md`（R1。本計画のexplore実測記録）
**デモ非依存**: チュートリアル・デモ台本はFSH無しで完結する構成を
維持する。凍結（11/5）までに未完なら12月世界公開準備へ持ち越す。

> **裁定済み（2026-08-26）**: 4判断すべて承認（条件付き含む）。実装
> 着手可（前段のみ。後段はopenehr-rails側前提修正待ち）。詳細は本文書
> 末尾「裁定反映」節を参照。前提修正のIssueドラフト:
> `docs/upstream/issues/openehr-rails--field-extractor-missing-terminology-bindings.md`。

## Step 1 explore実測結果（要約。詳細は`docs/reports/fsh-log.md` R1）

1. **中間表現は`FieldExtractor#entries`のみ**（`openehr-rails`
   `lib/openehr_rails/opt/field_extractor.rb:50-51`）。永続化された
   中間層は存在せず、JSON生成もリクエストの都度OPTから再構築する
   （`ProfileGenerator`・`ProfileRepository.from_registry`とも同型）
2. **源は(a)`FieldExtractor#entries`の共有が正**。(b)pathcards・
   (c)新設独立層は「二重導出禁止」に抵触するため却下。ただし
   **`FieldExtractor`自体に外部語彙binding抽出（`value_set_binding`/
   `code_binding`）が無い**ことが判明（既存JSONファサードの`valueSet`
   欠落バグと同根）。FSHの主要な価値（binding明示）を実現するには
   この抽出をgemレベルで追加する前提修正が必要
3. **v1範囲はJSON facadeが現に出力している要素**（Profile/Parent/
   cardinality/type/binding骨格/patternQuantity・patternCodeableConcept）。
   Sushi実際のコンパイルで`value_set_binding`→`from...(required)`・
   `code_binding`→`= SYSTEM#code "..."`（`patternCodeableConcept`と
   同一形状）の両方を実証済み
4. **Sushiは実在・動作確認済みだがNode依存はanlageに皆無**（新規
   インフラ追加の判断を要する。ネットワーク依存＝FHIR core/terminology
   パッケージの初回ダウンロードあり、`actions/cache`で緩和可能）
5. **SNOMEDリテラル予算**: 既存golden fixture
   （`spec/fixtures/pathcards/CardiologyEncounter.golden.json`）は
   実SNOMEDコードを`at0004`1件のみ保持し、`at0005`は
   `<REDACTED_SNOMED_CODE>`へ意図的に置換済み。FSH側のgolden fixtureも
   この予算内（新規の実コード文字列を増やさない）で構成する

## Step 2 計画

### 源の確定: (a) `FieldExtractor#entries`の共有

新設`OpenehrRails::Fhir::FshGenerator`（gem`lib/openehr_rails/fhir/`
直下、`ProfileGenerator`と同一の入力契約）が`FieldExtractor#entries`を
消費してFSH文字列を組み立てる。JSON/FSHは同一の中間表現から独立に
レンダリングされるのみで、OPTの意味論的解釈（archetype_id・rm_type・
code_list・required等の判定）はどちらも`FieldExtractor`一箇所に一本化
されたまま——二重導出は生じない。

### 前提修正: `FieldExtractor`へのbinding抽出追加（gemレベル、独立コミット）

`coded_text_constraints`（`field_extractor.rb:191-203`）の隣に、
anlageの`Opt::PathcardExtractor#bindings_for`/`#extract_code_bindings`
（`app/lib/opt/pathcard_extractor.rb:243-280`）と同型のロジックを
gem側へ移植する形で追加する:

- `value_set_binding`: `defining_code`が`C_CODE_REFERENCE`の場合、
  `reference_set_uri`を`field[:value_set_uri]`として追加
- `code_binding`: OPT文書の`term_bindings/items`から該当ELEMENTの
  `(system_uri, code)`を`field[:code_bindings]`（配列、複数terminology
  対応）として追加

この拡張により`ProfileGenerator#apply_value_constraints`
（`profile_generator.rb:125-129`）の既存`valueSet`欠落も副次的に
解消できる（`element[:binding][:valueSet] = field[:value_set_uri]`を
追加する1行修正）。**この前提修正はFSH機能に先行する独立コミットとし、
既存JSON回帰網（`spec/openehr_rails/fhir/profile_generator_spec.rb`
ほか）を通しつつ追加する。gemの公開API・実行時挙動に触れるため、
CLAUDE.md（openehr-rails）のticket-driven workflowに従い専用Issueを
要する（本Issueに従属する形での起票を承認事項1で提案）**。

### v1範囲（表、詳細は`docs/reports/fsh-log.md` R1）

Profile/Parent/Id/Title・code要素のpatternCodeableConcept・単一leaf
value[x]・複数leaf componentスライシング・DV_QUANTITYのunit・
DV_CODED_TEXTのbinding（前提修正後）。`magnitude_range`（min/max
Quantity制約）はJSON側が現状未出力のため対象外——JSON側の対応が
先決（本plan外の別判断）。

**v1検証対象の規模上限（裁定、2026-08-26）**: `mml_referral`級の大規模
テンプレート（多数entry・深いネスト）はv1の検証対象外とする。v1.1への
拡大判断は診断ドロップ（実テンプレートでの`FshGenerator`初回実行結果）
を見てから行う。

### TDD方針（実装着手後、t-wada方式）

1. **前提修正（`FieldExtractor`拡張）**: Red — 既存golden fixture
   （`spec/fixtures/opt/bmi_calculation.opt`ほかgem内蔵fixture）に対し
   `entries[].fields[].value_set_uri`/`code_bindings`が抽出されることを
   検証する新規spec。Green — 抽出ロジック追加。既存
   `profile_generator_spec.rb`の`valueSet`欠落も同時に埋める1行修正を
   同コミットに含める（原因が同一のため分離不要、コミットメッセージに
   「binding抽出追加に伴う既存欠落の同時解消」と明記）
2. **`FshGenerator`本体**: Red — `bmi_calculation.opt`（BMI・単一leaf・
   DV_QUANTITY）を既知の入力として、期待するFSH文字列（Profile/Parent/
   value[x]骨格）を固定するspec。Green — 実装
3. **binding写像**: Red — ProblemList相当のvalue_set_binding
   （ICD-11）・CardiologyEncounter相当のcode_binding（SNOMED、
   **`at0004`/`271649006`のみ再利用、新規の実コード文字列は追加しない**
   ——SNOMEDリテラル予算の遵守。C2防火壁条項と同根の慎重姿勢）を
   固定するspec
4. **Sushi検証（隔離）**: `FshGenerator`が生成したFSH文字列がSushiで
   実際にコンパイルできることを確認するrakeタスク（`rake fsh:verify`
   相当）。CI組み込みは承認事項3で判断
5. golden fixture（`.fsh`ファイル自体）の再生成規律はJSON golden
   fixtureの既存運用（`occurrences`訂正時の人間確認と同等の運用）を
   踏襲する

### Sushi検証の位置づけ（承認事項3で判断）

- FSH生成（純Ruby、`FshGenerator`）とSushi検証（Node、`fsh-sushi`）は
  明確に分離する。FSH生成自体はNode/npmセットアップの有無に関わらず
  動作する
**裁定（2026-08-26）**: v1はrakeタスク（ローカル・手動実行）まで。CI
組み込みは行わない。再判断は12月世界公開準備のタイミングで行う
（「FSHが公開機能として確定すれば、Node依存追加コストに見合う価値が
立つ」という条件付きで記録。evalハーネスと異なりSushiは合否を機械的に
判定する検証器でありCI適性自体は高いが、Node依存の新規追加という
インフラコストが確定的にでは無いため据え置く）。

### 出力の提供形

**裁定（2026-08-26）**: `rake fsh:export`（既存`pathcards:eval`/
`pathcards:backfill`と同型、anlage側）をv1とする。HTTPダウンロード
endpoint（`GET /fhir/profiles/:id.fsh`）・ファサード隣接ルートへの
フォーマット追加はv1.1へ。

### コミット分割（実装フェーズ、Codex起動時の目安。2段構成）

**前段（rails待ちの間に先行着手可、binding非依存）**:

1. `FshGenerator`本体（gem、v1範囲のうちbinding以外: メタデータ・
   単一leaf `value[x]`・複数leaf `component`スライシング・
   `DV_QUANTITY`の`patternQuantity`）
2. Sushi検証rakeタスク（anlage側、非binding部のFSHで動作確認）
3. `rake fsh:export`（anlage側、出力提供形v1）

**後段（openehr-rails側の前提修正完了がブロッカー）**:

4. binding写像（gem、`FshGenerator`への統合。`FieldExtractor`が
   `value_set_uri`/`code_bindings`を持つようになった後に着手）
5. binding込みgolden fixture更新・Sushi実コンパイル確認（SNOMEDリテラル
   予算を遵守、`at0004`/`271649006`のみ再利用）

## 裁定反映（2026-08-26）

### 判断1: 前提修正、独立Issue化を承認（条件付き）

帰属はopenehr-rails（`FieldExtractor`）。凍結前実装を承認——理由は
(a) FSHのbindingを実現する上でのブロッカーであること、(b) 既存JSON
facadeの`valueSet`欠落バグ自体の是正であること、の2点。Anlageの
`Opt::PathcardExtractor`（`bindings_for`/`extract_code_bindings`）を
参照実装とする。

**段取り**: anlage（本セッション）がIssueドラフトを作成——WP2の知見
（`docs/upstream/issues/openehr-ruby--opt-parser-crash-on-c-code-reference.md`
＝`skoba/openehr-ruby#30`・CLOSED、`docs/upstream/issues/
openehr-ruby--opt-parser-ignores-term-bindings.md`＝`skoba/
openehr-ruby#31`・OPEN、の2件の既存調査を根拠に含める）とfacade欠落の
実測を根拠とし、binding 2種（`value_set_binding`/`code_binding`）の
要求仕様を明記——を人間中継でopenehr-railsへ送り、rails側で
explore→plan→ゲートを別途行う。新テンプレート実戦2号（`skoba/
anlage#10`のCommitter実装に続く2件目）・openehr-rails 0.5.0の第一弾
という位置づけ。ドラフト: `docs/upstream/issues/
openehr-rails--field-extractor-missing-terminology-bindings.md`

### 判断2: v1範囲、承認

上記v1範囲表のとおり承認。`mml_referral`級の大規模テンプレートはv1
検証対象外、v1.1判断は診断ドロップ後に行う（本文書「v1サブセットの
範囲確定」節末尾に明記済み）。

### 判断3: Sushi、rakeタスク（ローカル・手動）まで

CI組み込みは12月世界公開準備時に再判断（FSHが公開機能として確定
すれば価値が立つ、という条件付きで記録。本文書「Sushi検証の位置づけ」
節に明記済み）。

### 判断4: 提供形、rake exportをv1

HTTPルートはv1.1へ（本文書「出力の提供形」節に明記済み）。

### 実装順序

openehr-rails側の前提修正完了がFSH実装のbinding部のブロッカー。
非binding部（Profile/cardinality/型/単位）は前提修正を待たず先行
着手可——本文書「コミット分割」節を前段/後段の2段に分けた。

### 追記1（2026-08-26）: 構造条項——将来のgem分離に備えた実装形

FHIR橋渡し層（FSHエミッタ・StructureDefinition生成・将来のFHIR
リソースインスタンス変換）の恒久配置は**衛星gem`openehr-fhirbridge`
として分離する方針を確定**した（`docs/backlog.md` 5項「FHIR橋渡し層の
恒久配置」参照）。依存方向は`openehr`のみ（Rails非依存）。スコープ
原則: `openehr-ruby`はopenEHR仕様定義物のみを扱い、他規格（FHIR等）
への写像は橋gem側に置く。

移行条件（いずれか）: Anlage外の第二消費者の出現／12月世界公開
パッケージング。前提作業: OPT平坦化（`FieldExtractor`相当）の
非Rails化（gem再編・第2巡以降）。

**それまでの実装規律**: `FshGenerator`本体・binding写像ロジックは、
現時点でopenehr-rails gem内に置く（Step 2「源の確定」節どおり）が、
**純Rubyモジュール＋薄いRailsアダプタ**の構造を守る——`FshGenerator`
自体は`FieldExtractor#entries`（Hash配列、Rails/ActiveRecordに非依存な
データ形）のみを入力に取り、Railsのモデル・コントローラ層には一切
触れない形で実装する。これにより、移行条件が満たされた時点で
`FshGenerator`本体を`openehr-fhirbridge`へそのまま移設でき、
呼び出し側（`ProfilesController`・rakeタスク）だけを薄いアダプタとして
差し替えれば済む。実装フェーズのコミットでこの境界を意識した設計
（`FshGenerator`が`ActiveRecord::Base`や`Rails`名前空間へ依存しないこと）
をレビュー観点に加える。

## Verification（実装着手後）

- `bundle exec rspec`（gem・anlage双方の新規specファイル含む）が全件green
- `FshGenerator`が生成したFSHがSushiで実際にコンパイルできることを確認
  （0 Errorsで完了、生成StructureDefinitionのbinding/patternCodeableConcept
  が期待どおりであることを確認）
- 前提修正により`profile_generator_spec.rb`の`valueSet`欠落が解消される
  ことを確認
- 新規の実SNOMEDコード文字列を追加していないこと（golden fixture差分
  レビューで確認）
