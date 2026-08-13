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
