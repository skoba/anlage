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
