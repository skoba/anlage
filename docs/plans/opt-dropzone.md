# OPT Dropzone 実装計画（Phase 0 成果物）

作成日: 2026-08-13
ステータス: **承認済み — 実装開始**

## 決定事項（2026-08-13 承認）

- **Q1: 案A（解釈方式を新規実装）を採用。** 既存の `TemplateUploader` /
  `RuntimeScaffolder` / `openehr:scaffold` は使わない。低レベルの
  `OpenehrRails::Opt.parse` と `OpenehrRails::Opt::FieldExtractor` のみ
  再利用する。`/openehr` admin engine は別系統として併存可（マウントは
  Slice 0 で判断）。
- **DB: SQLite3。** `web_template` は `json` 型カラムとする
  （Postgresの`jsonb`ではない）。
- **JS: importmap。** esbuild等のバンドラは導入しない。

## 0. 前提の食い違い（最初に確認）

`anlage` リポジトリは本セッション開始時点で**空ディレクトリ**だった
（Gemfile も app/ も存在しない）。「openehr-rails-startup」という単独リポジトリも
`/home/skoba/src` 配下に存在しない。

調査の結果、それに相当するものは **`openehr-rails` gem 同梱の Rails
アプリケーションテンプレート** だった:

- `/home/skoba/src/openehr-rails/templates/openehr_template.rb`
  （`rails new myehr -m .../openehr_template.rb` で実行する Thor テンプレート）

このテンプレートは `openehr:install` を実行し、admin engine
（`/openehr` にマウント）・テンプレートレジストリ・RM永続化層一式を持つ
新規Railsアプリを一括生成する。**anlage はまだこれで生成されていない。**

→ Phase 1 実装の最初のステップとして、まずこのテンプレートで `anlage` を
生成することを提案する（DBは `--database=sqlite3` を推奨、理由は後述）。
承認いただければ実行する。

## 1. 最重要の発見: 依頼機能の大部分が openehr-rails に既に存在する。ただし方式が違う

`openehr-rails`（`/home/skoba/src/openehr-rails`, gem version 0.4.0,
`README.md` に記載）は既に「OPTをドラッグ&ドロップ→レジストリ登録→UI稼働」を
実装済みだが、**「コード生成」方式**である。依頼書のコンセプトは
「コード生成ではなく実行時解釈」を明言しており、ここが正面から衝突する。

### 既存（openehr-rails）の方式: 生成 → migrate → reload

- `app/controllers/openehr_rails/templates_controller.rb` (`index`
  action の view: `app/views/openehr_rails/templates/index.html.erb`) —
  ドラッグ&ドロップの dropzone、`fetch` + `FormData` で
  `POST /openehr/templates` に送信、既に実装済み。
- `lib/openehr_rails/template_uploader.rb` — アップロードされた `.opt` を
  `app/templates/operational/` に保存し `OpenehrTemplate.from_opt_file` で
  レジストリに登録。
- `lib/openehr_rails/template_importer.rb` — URL からの取り込み版（依頼の
  Phase 2「URLドロップ」に相当する機能が既にある）。
- `lib/openehr_rails/runtime_scaffolder.rb` —
  「Generate UI」ボタン押下で **`rails g openehr:scaffold` ジェネレータを
  アプリ内から実行**し、model / migration / controller / views / routes /
  locale / request spec を**ファイルとして書き出し**、
  `ActiveRecord::MigrationContext#migrate` で migrate、
  `Rails.application.reload_routes!` でルート再読込する
  (`runtime_scaffolder.rb:58-71`)。
- `lib/generators/openehr/scaffold/scaffold_generator.rb` — 実際に
  `app/models/#{model_name}.rb` 等を `template` メソッドで書き出す
  （コード生成そのもの）。

つまり「ドロップすると動く」のuxは実現されているが、内部は
「ドロップ→**その場でコードを生成しファイルに書く**→migrate→ルート再読込」
であり、依頼書が明示的に禁止する「コード生成」そのものである。

### 依頼書が要求する方式: 解釈 → DB登録 → リクエスト時レンダリング

依頼書のコンセプトは、`GET /forms/:template_id` のような**固定ルート**が
リクエストの都度レジストリの `web_template`（中間表現）を解釈してフォームを
描画する、ファイル書き出しなしのモデルである。

### 質問（要判断・実装は保留）

**Q1. どちらの方式で進めるか？**

- **案A（推奨）**: 依頼書どおり「解釈方式」を anlage 側に**新規実装**する。
  ただし低レベルの部品（後述の `OpenehrRails::Opt.parse` /
  `OpenehrRails::Opt::FieldExtractor`）は再利用し、
  `TemplateUploader` / `RuntimeScaffolder` / `TemplatesController` /
  `openehr:scaffold` ジェネレータは**使わない**。admin engine
  (`/openehr`) はそのまま併存させ、anlage独自のカタログ/フォームは
  ホストアプリ側の固定ルートとして別途実装する。
- **案B**: 既存の「Generate UI」（コード生成方式）をそのまま使い、
  依頼書の「試着室」「即座に稼働」という**体験**だけ移植する
  （＝コンセプトの「コード生成はしない」を諦める）。

案Aで進めることを推奨する。理由: 依頼書がコンセプトとして明言している
「メディアファイルとして実行時解釈する」という差別化ポイントは、既存の
コード生成方式では実現できないため。承認をお願いしたい。

**Q2. 既存の `/openehr` admin engine とホストアプリの新ルートの共存範囲は？**

案Aを採る場合、`/openehr` エンジンの独自レジストリ (`openehr_templates`
テーブル、`OpenehrTemplate` モデル、`TemplateRegistry` concern) と、
依頼書が指定する新テーブル（`templates` または別名、checksum/status等
持つ）が**別テーブルとして併存**することになる。二重管理に見えるが、
これは gem の想定利用法（コード生成デモ用）とアプリ固有機能
（解釈方式デモ用）の役割分担として意図的に分けるのが良いと考えている。
`/openehr` エンジンを mount しない、という選択肢もある。要相談。

## 2. 根拠付き調査結果（事実）

### 2.1 OPTパースAPI

- `OpenehrRails::Opt.parse(opt_file_or_raw_xml)` →
  `OpenEHR::AM::Template::OperationalTemplate` を返す
  (`/home/skoba/src/openehr-rails/lib/openehr_rails/opt.rb:1-8`)。
- 実体は `OpenehrRails::Opt::Parser`
  (`lib/openehr_rails/opt/parser.rb`)。これは openehr-ruby の
  `OpenEHR::Parser::OPTParser` (`/home/skoba/src/openehr-ruby/lib/openehr/parser/opt_parser.rb`)
  のサブクラスで、**生XML文字列でもファイルパスでも受け付けるよう
  `#parse` をオーバーライド**している
  （`raw_xml_content?` で先頭が `<` かどうか判定。UTF-8 BOM対応込み、
  `opt/parser.rb:14-49`）。試着室のプレビュー用に、アップロードされた
  ファイルの中身をディスクに書かず直接パースできる。
- 内部で `Nokogiri::XML::Document.parse(source)` → `remove_namespaces!`
  している (`opt/parser.rb:20-21`)。**NONET・NOENT等の明示指定は無い**
  （後述 2.6 のXXE課題）。

### 2.2 web template 相当の中間表現

- `OpenehrRails::Opt::FieldExtractor`
  (`lib/openehr_rails/opt/field_extractor.rb`) が該当する。
  `OperationalTemplate` の制約木を辿り、ELEMENT を**フラットな配列**
  として抽出する。各フィールドは Hash:
  `name, label, path(RMパス), rm_type, node_id, archetype_id,
  column_type, units, magnitude_range, code_list, code_labels,
  terminology_id, required, value_code_map` など
  (`field_extractor.rb:8-21` のコメント + `build_field` 実装)。
- `DV_QUANTITY` → `:float` + `units` + `magnitude_range`（min/max）、
  `DV_CODED_TEXT` → `:string` + `code_list`/`code_labels`、
  `DV_ORDINAL`/`DV_SCALE` も同様に選択肢化 — 依頼書の「制約→UI対応表」
  と型のマッピングはほぼこのまま使える
  (`field_extractor.rb:26-41, 174-215`)。
- **リクエストの都度計算**であり、事前生成・キャッシュはしていない
  （`TemplateRegistry#form_fields` は毎回 `OpenehrRails::Opt.parse` する
  `template_registry.rb:56-61`）。つまりこの部品自体は既に「解釈方式」
  向きにできている。ただし occurrences（0..*の繰り返し）はエントリ単位
  でしか見ておらず、要素単位の繰り返しfieldset生成支援は無い
  （`entry[:occurrences]` はあるが `fields` には反映されない）。

### 2.3 フォーム描画エンジン

- **専用の「解釈してフォームを描画するビュー層」は存在しない。**
  実際にブラウザに出るフォームは `openehr:scaffold` ジェネレータが
  `app/views/.../{index,show,new,edit,_form}.html.erb` として**都度
  ファイルに書き出す ERB テンプレート**
  (`lib/generators/openehr/scaffold/scaffold_generator.rb:65-71`、
  テンプレート本体は `lib/generators/openehr/scaffold/templates/views/`)。
- したがって依頼書の「`GET /forms/:template_id` がレジストリを解釈して
  描画する」という部分は**新規実装が必要**。`FieldExtractor` の出力を
  入力にすれば実現できる見込みが高い。

### 2.4 composition の保存機構

- 既存の保存機構は**スキャフォールドされたARモデル前提**でかなり作り
  込まれている:
  - `OpenehrRails::Storable` — モデルに `FIELD_MAP` を持たせ保存時に
    RM Composition を組み立てる。
  - `OpenehrRails::Rm::RmObjectBuilder` / `GraphBuilder` /
    `GraphPersister` / `CanonicalSerializer` — 型付きノードグラフ
    (`openehr_rm_*` テーブル) とcanonical JSON (`rm_composition`
    カラム) の両方に永続化。
  - これは依頼書が要求する「単純な jsonb 1カラムの composition 保存」
    より遥かにリッチだが、**スキャフォールドされたモデルのクラス
    （`class_name`, `FIELD_MAP`）に依存**しており、案Aの「モデルを
    生成しない」方針とは前提が合わない。
- 案Aでは `compositions#create` は依頼書どおり素朴に
  `web_template` + 送信パラメータから composition の jsonb を組み立てて
  保存する軽量な自作实装が必要。openehr-ruby の
  `OpenEHR::RM::CompositionFactory.create_from_json`（README.rdoc に
  記載）が使える可能性があるが、**未調査**（下記「不明点」参照）。

### 2.5 FHIR facade / StructureDefinition

- 存在する: `lib/openehr_rails/fhir/{profile_generator,
  profile_repository, resource_registry, capability_statement,
  serializer, deserializer, type_map}.rb`、
  `app/controllers/openehr_rails/fhir_controller.rb`。
  `GET /openehr/fhir/StructureDefinition/:id` 等。
  README 記載の通り `OBSERVATION→Observation` 等の型マッピング
  (`Fhir::TypeMap`) から自動導出。
- ただし `resource_registry` はスキャフォールドされたモデル
  （`FIELD_MAP` を持つクラス）を前提にしている可能性が高い
  （**未確認**、profile_repository.rb 未読）。案Aで「モデル生成なし」
  の場合、この機構がそのまま使えるかは Phase 3 着手時に要再調査。
  依頼書でも Phase 3 は「gemの機能状況次第」としており、現時点では
  スコープ外として問題ない。

### 2.6 レジストリのテーブル定義（現状 vs 依頼仕様）

- 現状 (`lib/generators/openehr/install/templates/migrations/create_openehr_templates.rb`):
  `template_id(string, unique index), name, content(text),
  template_type(string), version(string)`。
  **checksum, status, dropped_at, dropped_by, web_template は無い。**
- `TemplateRegistry` concern (`template_registry.rb:15-16`) は
  `template_id` の**unique**バリデーションのみ（依頼仕様の
  `[template_id, version]` 複合indexとは異なる — 同一template_idの
  再バージョン登録を現状の仕組みは想定していない）。
- → 案Aでは依頼仕様どおりの新テーブル（`templates` または別名）を
  anlage 側に新規migrationで作る。既存 `openehr_templates` とは別物。

### 2.7 XXE対策

- `Nokogiri::XML::Document.parse(source)` の呼び出しは openehr-ruby
  (`opt_parser.rb:43`, `xml_archetype_parser.rb:33`) にも openehr-rails
  のオーバーライド (`opt/parser.rb:20`) にも見られるが、**いずれも
  `Nokogiri::XML::ParseOptions`（NONET/NOENT禁止等）を明示していない**。
  Nokogiri/libxml2 の新しめのバージョンは既定で外部実体解決を無効化
  している場合が多いが、**バージョン依存であり保証ではない**。
- gem 本体を改変しないという指示があるため、anlage 側では
  **プレビュー/登録エンドポイントに到達する前段で** own の XXE-safe
  Nokogiri チェック（`NONET | NOENT` を明示的に無効化した設定で一度
  パースしてみて、DOCTYPE/external entityを検知したら拒否する等）を
  アダプタとして持たせる。加えて `docs/upstream-candidates.md` に
  「`OpenehrRails::Opt::Parser` に安全なデフォルトの `ParseOptions` を
  明示すべき」という改善提案を記録する。

### 2.8 サンプルOPT（fixture）

- **ダミー捏造は不要。** `/home/skoba/src/openehr-rails/demo_assets/templates/`
  に実データが3件存在:
  `bmi_calculation.opt` (80,158 bytes), `problem_list.opt` (42,599
  bytes), **`patient_blood_pressure.opt` (69,561 bytes)** — 依頼書が
  「私が用意する」としていた Blood Pressure テンプレートに一致する
  実物がここに既にある。ネットワーク取得不要でローカルにある。
  anlage の `spec/fixtures/opt/` 等にコピーして使うことを提案する
  （openehr-rails リポジトリ自体は改変しない。コピーのみ）。

## 3. 不明点（推測せず質問として列挙）

1. ~~DB~~ → **決定: SQLite3**（上記「決定事項」参照）。
2. **RailsバージョンとRuby**: gemspec は Rails `>= 7.0, < 9.0`、Ruby
   `>= 3.3.0` を要求。`rbenv`/`.ruby-version` 等、この環境で使う
   Ruby/Railsの具体バージョンをどうするか（`openehr-rails` 自体の
   `.ruby-version` は未確認・要合わせ）。Slice 0 実施時に環境のRuby
   バージョンを確認して決める。
3. ~~JS構成~~ → **決定: importmap**（上記「決定事項」参照）。
4. **openehr-ruby の `CompositionFactory.create_from_json`
   （README.rdoc記載）の入出力形式**: 未読・未検証。案Aの
   `compositions#create` の実装方式（自前で jsonb を組むか、この
   ファクトリ経由で正規RM composition を作ってから JSON化するか）を
   決めるために、次の作業ブロックで `lib/openehr/rm/composition_factory.rb`
   相当を読む必要がある。
5. **`/openehr` engineを anlage にマウントするか**: 上記 Q2。マウントする
   場合、依頼仕様のルート（`templates`, `forms/:template_id` 等）との
   パス衝突は無い（enginは `/openehr` 配下）が、テンプレートレジストリが
   2系統になる点をどう案内するか。

## 4. 実装計画（承認後に着手する薄いスライス）

前提: 上記 Q1 で **案A（解釈方式・新規実装、既存の低レベル部品は再利用）**
が承認された場合の計画。

### Slice 0: 土台
- `openehr_template.rb` アプリテンプレートで `anlage` を生成
  （DB選択はQ1回答待ち）。`openehr-rails` は `path:` 参照
  （`OPENEHR_RAILS_PATH=/home/skoba/src/openehr-rails`）。
- commit: 「anlageを生成」

### Slice 1: レジストリ (Phase1)
- `templates` テーブル migration（依頼仕様どおり: template_id, version,
  source_xml, web_template, status, checksum(unique), dropped_at,
  dropped_by / 複合index [template_id, version]）。
- `Template` モデル + `SHA256` checksum算出 + `from_opt_xml` 相当の
  クラスメソッド（`OpenehrRails::Opt.parse` 呼び出し）。
- model spec。

### Slice 2: XXE安全パース + プレビュー(試着室) (Phase1)
- anlage側 `Opt::SafeParser`（仮称）アダプタ: NONET/NOENT無効化を明示
  → `OpenehrRails::Opt.parse` に委譲。
- `POST /templates/preview`: サイズ上限5MB・拡張子チェック・XXEチェック
  → `FieldExtractor` でサマリ算出 → Turbo Frame でプレビュー
  （登録はまだしない）。
- request spec: 正常系 / サイズ超過 / 拡張子不一致 / XXE攻撃ペイロード
  （DOCTYPE付きXML）で拒否されること。

### Slice 3: 登録 + カタログ (Phase1)
- `POST /templates`: checksum重複チェック → 登録 → Turbo Stream で
  カタログにカード追加。
- 全画面 dropzone Stimulus controller（dragenter オーバーレイ）。
- 同一checksum再送信 → 登録済み通知。

### Slice 4: フォーム稼働 + composition保存 (Phase1)
- `GET /forms/:template_id`: `web_template` を解釈してフォーム描画
  （DV_QUANTITY→number min/max/step, DV_CODED_TEXT→select 等）。
- `POST /compositions/:template_id`: バリデーション→保存
  （不明点4の回答を反映）。
- 一覧・詳細画面。
- system spec（fixtureは `patient_blood_pressure.opt` を使用）。

### Phase 2 / 3
依頼書のとおり。Phase 2 着手前に semantic diff・バージョニングの
テーブル設計（superseded遷移）を改めて確認する。Phase 3 は FHIR facade
再利用可否の再調査結果を踏まえて計画し直す。

## 5. 汎用化候補（先出し）

`docs/upstream-candidates.md` に以下を記録済み（詳細はそちら参照）:

- `OpenehrRails::Opt::Parser` に XXE-safe な `ParseOptions` を既定にする
  改善（openehr-rails側）。
- 「解釈方式」でのフォーム描画に使える薄いレンダラを
  `OpenehrRails::Opt::FieldExtractor` の出力から作る場合、汎用部分は
  openehr-rails 側にライブラリとして還元できる可能性がある
  （anlage固有のUI/Stimulus部分を除く）。
