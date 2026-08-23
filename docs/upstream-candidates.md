# 汎用化候補（openehr-rails / openehr-ruby へ還流すべきもの）

anlage 固有ではなく gem 側に置くべきと気づいた汎用機能をここに記録する。
gem 本体は改変しない（anlage 内で進め、還流は別途相談・PR化する）。

## 1. XXE-safe な Nokogiri ParseOptions をデフォルトにする

- 対象: `openehr-ruby` の `OpenEHR::Parser::OPTParser#parse`
  (`lib/openehr/parser/opt_parser.rb:43`) および
  `XMLArchetypeParser` (`lib/openehr/parser/xml_archetype_parser.rb:33`)、
  それを継承する `openehr-rails` の `OpenehrRails::Opt::Parser#parse`
  (`lib/openehr_rails/opt/parser.rb:20`)。
- 現状: `Nokogiri::XML::Document.parse(source)` を `ParseOptions` 指定
  なしで呼んでいる。
- 提案: `Nokogiri::XML::ParseOptions::NONET | ...NOENT を明示的に無効化`
  したデフォルトを与える（外部ネットワーク遮断・外部実体の非解決を
  ライブラリ側で保証する）。信頼できない入力（Web経由のアップロード）
  をパースするあらゆるアプリで有効な防御になるため、個々のアプリ側
  アダプタで都度対策するより gem 側で保証する方が筋が良い。
- 還流先: openehr-ruby（低レベルパーサ）が本来の置き場所。
  openehr-rails 側は継承しているだけなので upstream 側が直れば自動的に
  恩恵を受ける。
- 暫定対応: anlage では独自の安全ラッパーで先にパースを検証してから
  gem の parse を呼ぶ（`docs/plans/opt-dropzone.md` Slice 2 参照）。
- **ステータス: Issue ドラフト済み**
  （`docs/upstream/issues/openehr-ruby--xxe-safe-default-parse-options.md`）。
  ドラフト作成時に実装を再確認したところ、実際の `Opt::SafeParser`
  (`app/lib/opt/safe_parser.rb`) は Nokogiri ParseOptions ラッパーではなく
  DOCTYPE宣言の正規表現による事前拒否だった（計画書 Slice 2 の記載とは
  実装手段が異なる。ドラフト側は実装に合わせて記述済み）。
  起票後リンク: [skoba/openehr-ruby#33](https://github.com/skoba/openehr-ruby/issues/33)

## 2. 「解釈方式」フォームレンダラ

- 背景: `OpenehrRails::Opt::FieldExtractor` はコード生成前提の
  スキャフォールドジェネレータのために作られたフラット構造抽出器だが、
  実際にはリクエストの都度計算されており、「解釈方式」のフォーム描画
  にもそのまま使える設計になっている
  (`lib/openehr_rails/opt/field_extractor.rb`)。
- 提案: anlage でこの出力から直接 `<input>` 要素を組み立てる薄い
  レンダラを実装した後、Stimulus/Turbo に依存しない「制約→HTML属性
  対応表」部分（DV_QUANTITY→number min/max/step 等のマッピングロジック
  そのもの）が汎用的に使えると分かれば、openehr-rails 側に
  `OpenehrRails::Opt::FormFieldPresenter`（仮）のようなヘルパーとして
  切り出すことを検討する。
- 還流先: openehr-rails（Railsのform_with/tag helperに依存する部分が
  あるため openehr-ruby ではなくこちら）。
- ステータス: 未着手。Phase 1 Slice 4 の実装後に汎用化可能かどうか
  判断する。
- **再評価トリガー**: Slice 4 のレンダラ実装後、制約→HTML属性マッピングの
  汎用性を判断してから可否決定。

## 3. テンプレートレジストリの複合ユニーク制約・checksum・versioning

- 背景: 現状の `openehr_templates` テーブル
  (`lib/generators/openehr/install/templates/migrations/create_openehr_templates.rb`)
  は `template_id` の単純unique制約のみで、同一template_idの
  再バージョン登録（同一IDでcontentが変わるケース）を想定していない。
  anlage の依頼仕様は `[template_id, version]` 複合indexと checksumに
  よる冪等アップロードを要求しており、これは openEHR CDR
  （EHRbase等）の標準的な要件でもある。
- 提案: `openehr:install` が生成するレジストリ migration 自体に
  `checksum` (unique), `version`, `status`
  (active/superseded) を標準搭載する（今は `version` カラムのみあり
  未使用）。
- 還流先: openehr-rails（`lib/generators/openehr/install/templates/`）。
- ステータス: 未着手。anlage の Slice 1 で実装した設計が実証できたら
  提案する。
- **再評価トリガー**: Slice 1 の冪等アップロードがデモ準備期間を通じ
  無事故で運用できたら Issue 化（10月目安）。

## 4. RM値オブジェクト組み立てヘルパーの共通化

- 背景: `OpenehrRails::Rm::RmObjectBuilder`
  (`lib/openehr_rails/rm/rm_object_builder.rb`) は `dv_text` /
  `dv_coded_text` / `code_phrase` / `terminology_id` / `dv_date_time` /
  `party_self` / `party_identified` という、openEHR RM の値オブジェクト
  を組み立てる小さなprivateヘルパー群を持つ。これは
  `openehr_rm_*` グラフ（コード生成・Storable経路）専用に書かれている
  ため、解釈方式の anlage 側 `Opt::CompositionBuilder`
  (`app/lib/opt/composition_builder.rb`) では**同じ内容を独自に複製**
  した（`OpenehrRails.default_language` 等の設定値・
  `TerminologyService` のバリデーション要件に合わせる必要があり、
  車輪の再発明を避けるには公開APIとして切り出されている必要があった）。
- 提案: これらのヘルパーを `OpenehrRails::Rm::ValueBuilders`
  （仮）のような、グラフに依存しないモジュールとして切り出し、
  `RmObjectBuilder` 側もそれを `include`/委譲する形にリファクタリング
  する。そうすれば「コード生成経路」「解釈経路」の両方が同じ実装を
  使える。
- 還流先: openehr-rails（`lib/openehr_rails/rm/`）。
- ステータス: 未着手。anlage の Slice 4 で実装が安定したら、
  重複している具体的なメソッド一覧とともに提案する。
- **再評価トリガー**: Slice 4 安定後、Opt::CompositionBuilder と
  RmObjectBuilder の重複メソッド一覧を添えて Issue 化。

## 5. RMJSONSerializer ⇔ CompositionFactory.create_from_json のラウンドトリップが壊れている

- 背景（実際に踏んだバグ）: `OpenEHR::Serializer::RMJSONSerializer`
  (`lib/openehr/serializer/rm_json_serializer.rb`) は対象オブジェクトの
  **全 instance variable を機械的にreflectionでシリアライズ**する汎用
  walkerである。`DvDateTime#value=`
  (`lib/openehr/rm/data_types/quantity/date_time.rb:213-224`) は
  `@value` に加えて `@timezone`（ISO8601DateTimeパース結果、
  `_type => "TIMEZONE"`）等の**派生ivar**もインスタンス変数として保持
  するため、これも一緒にシリアライズされてしまう。
- 一方 `OpenEHR::RM::CompositionFactory.create_from_json` →
  `Factory#params` → `Factory#build` は `_type` ごとに
  `class_eval("#{type}Factory")` で対応する `<Type>Factory` クラスを
  動的解決するが（`lib/openehr/rm/factory.rb:34`）、**`TimezoneFactory`
  というクラスは存在しない**。そのため
  `RMJSONSerializer` が吐いたJSON（`timezone` キー付き）を
  `CompositionFactory.create_from_json` に**そのまま**渡すと
  `NameError: uninitialized constant OpenEHR::RM::Factory::TimezoneFactory`
  で例外になる。書き込み専用（生成→保存のみ）の用途では気づかないが、
  保存したJSONを読み戻して再度RMオブジェクト化しようとした瞬間に発覚する。
- 影響: anlage の `Opt::CompositionReader`
  (`app/lib/opt/composition_reader.rb`) はこの理由で
  `CompositionFactory.create_from_json` を使わず、パース済みJSON Hash
  を直接（`_type`/`archetype_node_id`/`data`/`events`/`items`/`value`
  という既知の形で）走査する実装にした。
- 提案（どちらか、または両方）:
  1. `RMJSONSerializer` 側で、`_type` が無い/`Factory`側で受け皿の無い
     派生ivar（`timezone`, `year`, `month`, `day`, `hour`, `minute`,
     `second`, `fractional_second`, `magnitude_status` 等、`value` から
     再導出可能な内部キャッシュ）を除外する。
  2. `Factory` 側に `TimezoneFactory`
     （`OpenEHR::AssumedLibraryTypes::ISO8601DateTime::Timezone` 相当を
     組み立てる）を追加する。
  どちらの場合も「RMJSONSerializerで吐いたJSONをcreate_from_jsonで
  読み戻すラウンドトリップ」を最低1件、gem側のテストに追加すべき
  （現状これを検証するテストが無いために気づかれていないと見られる）。
- 還流先: openehr-ruby（`lib/openehr/serializer/rm_json_serializer.rb`
  と `lib/openehr/rm/factory.rb`）。
- ステータス: 未着手。まずは上記の再現手順（DvDateTimeを含む
  Compositionをbuild→RMJSONSerializerでserialize→
  CompositionFactory.create_from_jsonでparse、の3行で再現する）を
  Issueとして起票することを推奨。
- **ステータス: Issue ドラフト済み**
  （`docs/upstream/issues/openehr-ruby--rmjson-serializer-roundtrip-broken.md`）。
  再現スクリプトを実際に実行して確認: 落ちるのは `_type` 付きHash値の
  派生ivar（`timezone` → `TimezoneFactory` 不在で NameError）のみで、
  スカラーの派生ivar（`year`/`month`/`day`等）はコンストラクタに黙って
  無視され例外にはならない。上記本文の「一緒にシリアライズされてしまう」
  という記述は正しいが、「落ちる」原因はtimezoneのようなHash値ivarに
  限られる点をドラフト側で精密化した。
  起票後リンク: [skoba/openehr-ruby#32](https://github.com/skoba/openehr-ruby/issues/32)

## 6. OPTParser が用語バインディングを読まない／C_CODE_REFERENCE でパースが落ちる

- 背景: パスカードWP0調査（`docs/design/pathcards-wp0-exploration.md` 2.7節）で
  `OpenEHR::Parser::OPTParser` が `term_bindings` 要素を読まないことを確認済み。
  さらに2026-08-22、Archetype Designer が DV_CODED_TEXT の defining_code に
  外部ターミノロジー参照を付けると出力する `<children xsi:type="C_CODE_REFERENCE">`
  （`referenceSetUri` 保持。実例: `spec/fixtures/opt/ProblemList.opt:323-334` の
  `terminology:http://id.who.int/icd/release/11/mms`）で、**パース自体が
  `NoMethodError` で失敗する**ことを実OPTで確認した。
- 原因: `XMLConstraintParsing#children`
  (`lib/openehr/parser/xml_constraint_parsing.rb:68`) が
  `send child.attributes['type'].text.downcase, ...` と xsi:type 名を
  そのままメソッド名にディスパッチするが、`c_code_reference` ハンドラが
  存在しない（`c_code_phrase` はある）。
- 提案: (a) `c_code_reference` ハンドラを追加し referenceSetUri を保持した
  CCodePhrase相当（またはCCodeReference型）を返す。(b) `term_bindings` の
  パースを `archetype_terminology` に追加する。少なくとも(a)は未知のxsi:typeで
  クラッシュしない防御（未知型はC_COMPLEX_OBJECT扱いにフォールバック等）と
  合わせて入れる価値がある。
- 還流先: openehr-ruby（`lib/openehr/parser/xml_constraint_parsing.rb` /
  `opt_parser.rb`）。
- 暫定対応（Anlage側・2026-08-22人間承認の方針）: パスカード抽出器は
  `templates.source_xml` に保持しているOPT原文を独自に再解析し、
  `term_bindings`（実例: `spec/fixtures/opt/CardiologyEncounter.opt:1029-1035`
  のSNOMED-CT）と `referenceSetUri` の両形式を取得する。C_CODE_REFERENCE
  クラッシュへのAnlage側対処（Parser派生クラスへのハンドラ追加等）は
  **不要になった（2026-08-22、openehr 2.3.1 bumpで解消。上記(a)参照）**。
- ステータス: 未着手（Issue起票候補）。
- **ステータス: Issue ドラフト済み（2件に分割）**
  - (a) C_CODE_REFERENCE クラッシュ（bug）:
    `docs/upstream/issues/openehr-ruby--opt-parser-crash-on-c-code-reference.md`
    — 起票後リンク: [skoba/openehr-ruby#30](https://github.com/skoba/openehr-ruby/issues/30)
    — **解消済み（openehr 2.3.1、2026-08-22）**: `C_CODE_REFERENCE` は
      `CCodeReference`（`reference_set_uri`保持）として正規にパースされるように
      なった。未知のxsi:type全般もフォールバック（warn＋C_COMPLEX_OBJECT扱い）で
      落ちなくなった。Anlage側は`openehr`を2.3.1にbumpして確認済み
      （`spec/fixtures/opt/ProblemList.opt`が素のgemで試着室まで到達）
  - (b) term_bindings 未読（enhancement）:
    `docs/upstream/issues/openehr-ruby--opt-parser-ignores-term-bindings.md`
    — 起票後リンク: [skoba/openehr-ruby#31](https://github.com/skoba/openehr-ruby/issues/31)

## 7. FieldExtractor が埋め込みCLUSTERノードのラベルを宿主アーキタイプの用語から誤引きする

- 背景（実OPTで確認・2026-08-22）: `OpenehrRails::Opt::FieldExtractor` の
  `term_text(archetype_id, code)` はエントリ（宿主アーキタイプ）の
  component_terminology だけを見るため、エントリ内に埋め込まれた
  C_ARCHETYPE_ROOT（CLUSTER）配下ノードのat-codeが宿主側の同名codeに衝突
  すると、**宿主側のラベルを返す**。
- 実例: `spec/fixtures/opt/LabResultReport.opt` で
  `CLUSTER.laboratory_test_analyte.v1` の at0001「分析結果」（同OPT 621-623行）が、
  宿主 `OBSERVATION.laboratory_test_result.v1` の at0001「Event Series」
  （同 1038-1040行）として抽出される。at0024「分析名」（686-688行）は宿主側に
  同codeが無いためnil→code文字列にフォールバックする。
- 提案: フィールドが属する直近の C_ARCHETYPE_ROOT の archetype_id で
  component_terminology を引く（ノード→所属アーキタイプの対応を抽出時に
  保持する）。
- 還流先: openehr-rails（`lib/openehr_rails/opt/field_extractor.rb`）。
- 影響: Anlage側パスカード抽出器（WP2）は FieldExtractor に依存せず
  OPT全ノードを自前走査する予定のため、抽出器側では正しいterminology
  スコープ解決を最初から設計に入れる（本件が設計根拠）。
- ステータス: 未着手。
- **ステータス: upstream で対応済み（2026-08-22 確認、起票せず）**。
  `openehr-rails` ローカルチェックアウトのコミット
  `f9291d4`（"Fix: FieldExtractor resolved terminology labels using
  the wrong archetype scope", `Fixes #25`）で修正済みと判明した
  （GitHub `skoba/openehr-rails` Issue #25、バージョン 0.4.0→0.4.1）。
  起票用に作成していたドラフトはそのまま調査記録として保存:
  `docs/upstream/issues/openehr-rails--field-extractor-wrong-terminology-scope.md`
- **Issue / PR リンク**（`gh` で実在確認済み、2026-08-22）:
  Issue [skoba/openehr-rails#25](https://github.com/skoba/openehr-rails/issues/25)
  （CLOSED） / PR [skoba/openehr-rails#26](https://github.com/skoba/openehr-rails/pull/26)
  （MERGED, `31675057590705faea1bbab3917ce1dc3c59ada6`）。
  修正設計文書は PR 本文が指す `docs/design/fix-terminology-scope-plan.md`
  （openehr-rails リポジトリ側）。
- **Anlage側の撤去対象workaroundについて**: 撤去すべきworkaroundは
  無い。WP2のパスカード抽出器が `FieldExtractor` に依存せず OPT
  全ノードを自前走査する設計は、本件の回避策としてではなく
  `term_bindings`/`referenceSetUri` 取得（台帳 #6b）等、
  `FieldExtractor` では原理的に取得できない情報を得るための独立した
  設計判断であり、その根拠は本件解消後も残存する。
  （冒頭に RESOLVED UPSTREAM 注記あり）。

## 8. `Archetype::ConstraintModel::CObject#path`が埋め込みC_ARCHETYPE_ROOT自身のnode_idブラケットを欠落させる

- 背景（2026-08-23、WP2 TODO 2着手前の実測で発見）: `spec/fixtures/opt/LabResultReport.opt`
  をパースし、`each_constraint_node`と同じ走査で全ノードの`.path`を実測すると、
  埋め込み`CArchetypeRoot`（`laboratory_test_analyte.v1`、node_id=`at0000`）自身の
  `.path`が`/content/data[at0001]/events[at0002]/data[at0003]/items`（末尾に
  `[at0000]`ブラケットが無い）となり、以降の子孫ノードすべてがこの欠落した
  pathを`parent_path`として継承する（実測: `items/items[at0001]`のように、本来
  `items[at0000]/items[at0001]`になるべき箇所で`[at0000]`が消える）。トップレベルの
  `/content`セグメントも同様にarchetype_idブラケットを持たない（`/content[archetype_id]`
  ではなく`/content`）。
- 原因（推定、未確定）: `CObject#path`（`lib/openehr/am/archetype/constraint_model.rb:126-128`）は
  `@path || calculate_path`というメモ化パターンで、一度計算されると`@path`に
  キャッシュされ再計算されない。`calculate_path`（同:158-169）は`node_id`を
  参照するが、OPTParser側でXML属性の読み込み順序によっては`path`アクセサが
  `node_id=`設定前に一度呼ばれてキャッシュが確定してしまう可能性がある
  （実装コード上の確証は未取得。再現手順は上記の実測スクリプトのみ）。
- 影響範囲: `Archetype#physical_paths`/`#logical_paths`（公開API、
  `lib/openehr/am/archetype.rb:128-135`）も内部で`node.path`を呼ぶため、
  同じ欠落を引き継ぐ。
- Anlage側の対応: WP2パスカード抽出器はこの`.path`を使わず、
  `openehr-rails/lib/openehr_rails/opt/field_extractor.rb:129-135`と同じ
  「`rm_attribute_name` + node_idがあれば`[atNNNN]`」を自前で連結する方式を
  採用する（`docs/design/wp2-plan.md` 1.2節）。FieldExtractorが`.path`を
  使わず独自にpath構築している理由も、恐らく本件と同種の問題を避けるため
  と推測される（未確認）。
- ステータス: 未着手（Issue起票候補）。再現手順の精密化（`node_id=`設定順序の
  実コード確認）が必要。

## 9. `OpenehrRails::Rm::GraphBuilder`がENTRY階層の正当なRM属性（language/encoding/subject等）でクラッシュする

- 背景（2026-08-23、`skoba/anlage#5`のPlan A実装で発見）: `OpenEHR::Serializer::RMJSONSerializer`
  が生成する正規canonical JSONでは、ENTRY（OBSERVATION等）のhashに
  `language`/`encoding`/`subject`（RM仕様上ENTRYが正当に持つ属性。
  `class Entry < CareEntry`の一部）が含まれる。しかし
  `OpenehrRails::Rm::GraphBuilder::RESERVED_KEYS`
  （`lib/openehr_rails/rm/graph_builder.rb:9-10`）は
  `%w[_type archetype_node_id archetype_details name uid feeder_audit links]`
  のみを構造走査から除外し、`language`/`encoding`/`subject`は含まない。
  結果、`build_children`（同ファイル63-77行目）がこれらをHash値として
  誤って子ノードと解釈し、`build_node`→`TypeMap.node_class_for('CODE_PHRASE')`
  で`ArgumentError: unknown RM node type "CODE_PHRASE"`となり全体が失敗する
  （`subject`側は`PARTY_SELF`等、同様に失敗し得る）。
- 再現: `Opt::CompositionBuilder`（Anlage側、`archetype_details`欠落は
  別件・8項ではなく`skoba/anlage#9`で追跡）の出力を
  `RMJSONSerializer`でシリアライズし、`OpenehrRails::Rm::CompositionCommitter.commit`
  へそのまま渡すと再現する（`spec/demo/support/height_seed.rb`が実装した
  回避策＝該当キーを事前削除、で解消することを実測確認済み）。
- 影響範囲: `GraphBuilder`は「`Storable#to_rm_composition`が出力する形」を
  主な入力契約として設計されている（クラスコメント参照）。Storable経由の
  ENTRYはlanguage/encoding/subjectを設定しない実装（`app/lib/opt/
  composition_builder.rb`とは異なる作り）である可能性があり、その場合
  gem内では従来顕在化しなかった可能性がある（未確認）。`RMJSONSerializer`
  の出力を`GraphBuilder`へ渡す経路（REST API等、`CompositionCommitter`の
  `owner: nil`分岐が示唆する用途）全般に影響し得る。
- Anlage側の対応: `spec/demo/support/height_seed.rb`で該当キーを
  `CompositionCommitter.commit`呼び出し前に削除する回避策を実装済み
  （`skoba/anlage#5`）。恒久対応はgem側`RESERVED_KEYS`の拡張、または
  `build_children`をRM属性のホワイトリスト方式に変える設計変更が
  考えられる。
- ステータス: 未着手（Issue起票候補）。

## 10. AQLパス解決の`ALLOWED_TERMINAL_HOPS`制限により`defining_code`/`code_string`へ到達不能

- 背景（2026-08-23、`skoba/anlage#5` Q2実装で発見）: `openehr` gemのAQLパス評価器
  （`lib/openehr/aql/engine/path_evaluator.rb:23`）は、Pathable宣言されていない
  値（DV_CODED_TEXT等）への終端ホップを`ALLOWED_TERMINAL_HOPS = %w[magnitude name value]`
  （同ファイル23行目）のみに限定している。ファイル冒頭のクラスコメントには
  「Expand only when a real query needs another one」（実クエリが必要とするまで
  拡張しない）と明記されており、意図的なスコープ限定と判断できる。
  この結果、DV_CODED_TEXTの`defining_code`（さらにその`code_string`）へ辿る
  パスは`navigate_terminal`（同78-84行目）で`unsupported path attribute`の
  `OpenehrRails::Aql::UnsupportedFeature`になり、**コード値そのものによる
  WHERE絞り込みができない**（表示ラベル値=`.../value/value`のみ照会可能）。
- 到達不能だった実クエリ原文（`skoba/anlage#5` Q2、`docs/demo/aql-queries.md`
  2節参照）:
  ```
  SELECT c/uid/value AS composition_uid,
         o/data[at0001]/items[at0073]/value/defining_code/code_string AS diagnosis_code
  FROM EHR e CONTAINS COMPOSITION c
       CONTAINS EVALUATION o[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
  WHERE o/data[at0001]/items[at0073]/value/defining_code/code_string
        MATCHES {"at0074", "at0075"}
  ```
- 実測したエラー: `OpenehrRails::Aql::UnsupportedFeature: unsupported path
  attribute "defining_code" on a OpenEHR::RM::DataTypes::Text::DvCodedText`
  （`docs/reports/demo-queries-log.md` R4に実行ログの要約あり）
- 回避に使った代替パス: `value/defining_code/code_string`→`value/value`
  （DvCodedTextの表示ラベル自体でのMATCHES。`docs/demo/aql-queries.md` 2節の
  採用形。コードではなくラベル文字列での一致になる点を明記済み）
- ステータス: 未着手（Issue起票候補。意図的スコープ限定である可能性が高く、
  起票する場合はenhancement扱いが妥当）。

## 11. AQLパス解決で`events/time`へ到達不能（イベント時刻での期間WHERE不可）

- 背景（2026-08-23、`skoba/anlage#5` Q4実装で発見）: `openehr` gemの
  `OpenEHR::RM::DataStructures::History::Event`系クラス
  （`lib/openehr/rm/data_structures/history.rb:21`）は`path_attribute :events,
  :summary`のみを宣言しており、`time`はPathable経路として宣言されていない。
  また`time`は10項の`ALLOWED_TERMINAL_HOPS`（`magnitude`/`name`/`value`）にも
  含まれないため、`navigate_terminal`でも拒否される。結果、**OBSERVATIONの
  イベント時刻（測定日時）を使った期間WHERE絞り込みが現行AQLエンジンでは
  一切実行できない**（10項と異なり、代替の終端ホップも存在しない——`time`
  自体がPathable/terminal両経路から漏れている）。
- 到達不能だった実クエリ原文（`skoba/anlage#5` Q4、`docs/demo/aql-queries.md`
  4節参照）:
  ```
  SELECT o/data[at0001]/events[at0002]/data[at0003]/items[at0004]/value/magnitude AS height,
         o/data[at0001]/events[at0002]/time/value AS measured_at
  FROM EHR e CONTAINS COMPOSITION c
       CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.height.v2]
  WHERE o/data[at0001]/events[at0002]/time/value >= "2026-01-01T00:00:00"
    AND o/data[at0001]/events[at0002]/time/value < "2026-07-01T00:00:00"
  ```
- 実測したエラー: `OpenehrRails::Aql::UnsupportedFeature: unsupported path
  attribute "time" on a OpenEHR::RM::DataStructures::History::PointEvent`
  （`docs/reports/demo-queries-log.md` R4に実行ログの要約あり）
- 回避に使った代替パス: OBSERVATIONのイベント時刻という切り口自体を諦め、
  `ProblemList.opt`のELEMENT値として保持されるDV_DATE_TIMEフィールド
  （at0003「臨床的に認識された日時」、`.../value`経由で到達可能）へクエリの
  対象そのものを差し替えた（`docs/demo/aql-queries.md` 4節の採用形）。
  ISO8601文字列同士の辞書順比較に依存する点も同節に注記済み。
- ステータス: 未着手（Issue起票候補。10項より制約が強く——代替ホップが
  存在しない——優先度は10項より高いと判断）。

## 12. `rm_version`の情報源がOPT/gem設定に存在しない

- 背景（2026-08-23、`skoba/anlage#9`実装で発見）: `OpenEHR::RM::Common::Archetyped::Archetyped`
  （gem`openehr-2.3.1` `lib/openehr/rm/common/archetyped.rb:201-222`）は
  `rm_version`を必須属性として要求する（nil/空文字で`ArgumentError`）が、
  OPTのXMLにはRMバージョンを表す要素が無く、`Template#web_template`
  （Anlage側、`app/models/template.rb`）にもgem`FieldExtractor`出力
  （`field_extractor.rb:105-121`）にも`rm_version`相当のキーは存在しない
  （実測確認: `docs/reports/issue9-log.md` R1）。
- gem全体を横断すると`"1.0.4"`が唯一の実測リテラル値として使われている
  （`storable.rb:93,145`、`canonical_serializer.rb:41`のフォールバック、
  `graph_builder.rb:33`の`details['rm_version'] || '1.0.4'`、
  `db/schema.rb:51`の`openehr_rm_compositions.rm_version`列デフォルト値）。
  つまりgem側もこの値を「どこかから供給されるもの」としてではなく
  ハードコードされたデフォルトとして扱っている。
- 本来はgemがOPT（またはテンプレート設定）からRMバージョンを供給すべき値の
  可能性がある——現行OPT仕様がRMバージョンを表現しない以上、gem側で
  「サポート対象RM version」を明示的な設定値として持つ設計の方が、
  各消費側（Anlage含む）でのリテラル値の重複を避けられる。
- Anlage側の対応: `Opt::CompositionBuilder::RM_VERSION = "1.0.4"`として
  定数化し、出所コメントを付して使用する（`skoba/anlage#9`）。
- ステータス: 未着手（Issue起票候補。既存の複数箇所のハードコードを
  gem側の一設定点に統合する提案として起票する場合はenhancement扱いが妥当）。
