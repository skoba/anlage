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
- CI組み込みの選択肢: (i) 新規`fsh_lint`ジョブを追加し
  `actions/setup-node`＋`npm install -g fsh-sushi`＋
  `actions/cache`で`~/.fhir/packages`をキャッシュ (ii) 手動実行のみ
  （evalハーネスと同じ扱い、`skoba/anlage#15`の先例に従い別Issue化）
- evalハーネスとの違い: Sushiは合否を機械的に判定する検証器であり
  CI適性は高い（eval是非判断の理由「rake taskは指標を表示するだけで
  合否判定器ではない」がここでは当てはまらない）。ただしNode依存の
  新規追加というインフラ判断が伴うため、承認事項として提示する

### 出力の提供形（承認事項4で選定）

- (i) ダウンロードendpoint（`GET /fhir/profiles/:id.fsh`）
- (ii) `rake fsh:export`（既存`pathcards:eval`/`pathcards:backfill`と
  同型、anlage側）
- (iii) ファサード隣接ルート（`profiles_controller`へのフォーマット
  追加）

### コミット分割（実装フェーズ、Codex起動時の目安）

1. `FieldExtractor`へのbinding抽出追加＋`ProfileGenerator`の
   `valueSet`欠落解消（gem、独立Issue）
2. `FshGenerator`本体（gem、v1範囲：メタデータ・value[x]・component
   スライシング）
3. binding写像（gem、`FshGenerator`への統合）
4. Sushi検証タスク＋出力提供endpoint（anlage側、承認事項3・4の裁定後）

### 承認が必要な判断

1. **前提修正の起票単位**: `FieldExtractor`のbinding抽出拡張を
   本Issue（`skoba/anlage#17`）に含めるか、openehr-rails側の独立Issue
   として先に起票するか。gemの公開API・実行時挙動に触れるため
   ticket-driven workflow上は独立Issueが必要（推奨: openehr-rails側で
   先行Issue起票、本Issueはそれに従属）
2. **v1範囲の確定**: 上記表の範囲で承認するか、`magnitude_range`も
   含めるか（含める場合はJSON側の対応修正が前提となり範囲が拡大する）
3. **Sushi検証のCI組み込み**: 組み込む（新規Node依存追加）か、
   手動実行のみに留めるか
4. **出力の提供形**: 上記3案のいずれか（複数選択も可）

## Verification（実装着手後）

- `bundle exec rspec`（gem・anlage双方の新規specファイル含む）が全件green
- `FshGenerator`が生成したFSHがSushiで実際にコンパイルできることを確認
  （0 Errorsで完了、生成StructureDefinitionのbinding/patternCodeableConcept
  が期待どおりであることを確認）
- 前提修正により`profile_generator_spec.rb`の`valueSet`欠落が解消される
  ことを確認
- 新規の実SNOMEDコード文字列を追加していないこと（golden fixture差分
  レビューで確認）
