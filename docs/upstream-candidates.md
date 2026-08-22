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
