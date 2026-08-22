# WP0 探索レポート：セマンティックパスカード基盤

- **対象**: `claude-code-prompt_semantic-pathcards.md` WP0
- **作成日**: 2026-08-19
- **範囲**: コード変更なし。読み取り専用調査のみ
- **凡例**: 各項目に `ファイルパス:行範囲` と実コード引用を付す。Anlageリポジトリ内は相対パス、
  gemはインストール実体（`/home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0`）
  および `openehr-rails` はローカルcheckout（`/home/skoba/src/openehr-rails`、`Gemfile:65` で
  path指定されAnlageから実際にロードされる実体）から引用する。確認できない事項は「不明」と明記する

---

## 1. Anlageの現構成

### 1.1 OPT取り込み経路

ドロップゾーンUI（[app/views/templates/index.html.erb:3-6](../../app/views/templates/index.html.erb#L3-L6)）：

```erb
<div data-controller="dropzone"
     data-dropzone-preview-url-value="<%= templates_preview_path %>"
     data-dropzone-register-url-value="<%= templates_path %>"
     data-action="dragover->dropzone#dragover dragenter->dropzone#dragenter dragleave->dropzone#dragleave drop->dropzone#drop">
```

ファイル入力とURLドロップ（CKM取り込み）の両方の入口が同ビュー内にある
（[app/views/templates/index.html.erb:14-21](../../app/views/templates/index.html.erb#L14-L21)）：

```erb
<input type="file" id="opt_file_input" accept=".opt,.xml,.json,.adl" multiple hidden
       data-dropzone-target="fileInput"
       data-action="change->dropzone#fileSelected">

<form data-action="submit->dropzone#importUrl">
  <input type="url" placeholder="https://ckm.openehr.org/..." data-dropzone-target="urlInput">
  <button type="submit">URLから取り込む</button>
</form>
```

ルートは3本のみ（[config/routes.rb:13-15](../../config/routes.rb#L13-L15)）：

```ruby
get  "templates",         to: "templates#index"
post "templates/preview", to: "templates#preview"
post "templates",         to: "templates#create"
```

サーバ側入口 `TemplatesController#read_validated_content` はURL指定があればURL取り込み、無ければ
ファイルアップロードを読む（[app/controllers/templates_controller.rb:127-131](../../app/controllers/templates_controller.rb#L127-L131)）：

```ruby
def read_validated_content
  return read_validated_url if params[:url].present?

  read_validated_upload
end
```

URLは `ckm.openehr.org` のみ許可（`ALLOWED_URL_HOSTS = %w[ckm.openehr.org].freeze`、同ファイル14行）し、
`OpenehrRails::Opt::RemoteFetcher.fetch(url)` で取得する（同ファイル170行）。アップロードサイズ上限は
`MAX_UPLOAD_SIZE = 5.megabytes`（同4行）、拡張子は `/\.(opt|xml|json)\z/i`（同8行）。

パースは `parse_upload` → `Template.build_from_opt_xml` で行われる
（[app/controllers/templates_controller.rb:182-187](../../app/controllers/templates_controller.rb#L182-L187)）：

```ruby
def parse_upload(content)
  Template.build_from_opt_xml(content)
rescue Opt::UnsafeTemplate, Template::InvalidTemplate => e
  render_upload_error(e.message)
  nil
end
```

パーサ呼び出しの実体は `Template.build_from_opt_xml`（[app/models/template.rb:22-39](../../app/models/template.rb#L22-L39)）：

```ruby
def self.build_from_opt_xml(source_xml)
  opt = Opt::SafeParser.parse(source_xml)
  raise InvalidTemplate, "template has no template_id" if opt.template_id.value.to_s.empty?

  extractor = OpenehrRails::Opt::FieldExtractor.new(opt)
  new(
    template_id: opt.template_id.value,
    version: "1.0.0",
    source_xml: source_xml,
    web_template: build_web_template(opt, extractor),
    status: "active",
    checksum: Digest::SHA256.hexdigest(source_xml)
  )
```

`Opt::SafeParser`（Anlage独自、XXE対策のDOCTYPE拒否ラッパ）は内部で `OpenehrRails::Opt.parse` を呼ぶ
（[app/lib/opt/safe_parser.rb:11-21](../../app/lib/opt/safe_parser.rb#L11-L21)）：

```ruby
class SafeParser
  DOCTYPE_PATTERN = /<!DOCTYPE/i

  def self.parse(source_xml)
    if source_xml.to_s.b.match?(DOCTYPE_PATTERN)
      raise UnsafeTemplate, "DOCTYPE declarations are not allowed in OPT uploads"
    end

    OpenehrRails::Opt.parse(source_xml)
  end
end
```

保存先はDBの `templates` テーブル（ファイルシステム保存なし）。全列
（[db/schema.rb](../../db/schema.rb)、`create_table "templates"` ブロック、163-176行）：

```ruby
create_table "templates", force: :cascade do |t|
  t.string "checksum", null: false
  t.datetime "created_at", null: false
  t.datetime "dropped_at"
  t.string "dropped_by"
  t.text "source_xml", null: false
  t.string "status", default: "active", null: false
  t.string "template_id", null: false
  t.datetime "updated_at", null: false
  t.string "version", default: "1.0.0", null: false
  t.json "web_template"
  t.index ["checksum"], name: "index_templates_on_checksum", unique: true
  t.index ["template_id", "version"], name: "index_templates_on_template_id_and_version", unique: true
end
```

`source_url`（CKM由来URL）に相当する列は存在しない。**取り込み元URLはprovenanceとして保存されない**
（欠落。4.6節参照）。

### 1.2 実行時レジストリ

実行時レジストリはActiveRecordモデル `Template`（`templates`テーブル）そのもの。キャッシュ・シングルトンは
使わず毎リクエストDBを引く（[app/models/template.rb:3-16](../../app/models/template.rb#L3-L16)）：

```ruby
class Template < ApplicationRecord
  class InvalidTemplate < StandardError; end

  STATUSES = %w[active superseded].freeze

  validates :template_id, presence: true
  validates :version, presence: true
  validates :checksum, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :template_id, uniqueness: { scope: :version }

  scope :active, -> { where(status: "active") }

  has_many :compositions, dependent: :destroy
```

実行時参照例: `FormsController#show` の `Template.active.find_by!(template_id: params[:template_id])`、
`CompositionsController#create` の同呼び出し、`Fhir::ProfilesController#all_profiles` の
`Template.active.flat_map`。

`openehr_templates`テーブルに対応するモデル `OpenehrTemplate` は
`OpenehrRails::TemplateRegistry` を include するだけの1クラスで（[app/models/openehr_template.rb:1-3](../../app/models/openehr_template.rb#L1-L3)）、
Anlage本体のコントローラ・ビューからの参照は無い（grep確認済み。`config/initializers/openehr.rb`の
コメントに `OpenehrTemplate.from_opt_file` という記述があるのみで、実際の呼び出しはAnlage内に無い）。
このメソッドがgem側 `TemplateRegistry` に実在することは1.7節で確認した。

### 1.3 ドロップゾーンのフック可能点

「投入成功」が確定する正確な行は `TemplatesController#create` の73行 `if template.save` であり、
直後の74行で旧バージョンをsupersedeしてからレスポンスを返す
（[app/controllers/templates_controller.rb:61-88](../../app/controllers/templates_controller.rb#L61-L88)）：

```ruby
def create
  content = read_validated_content || return

  if (existing = Template.find_by_checksum(content))
    return render_notice("already registered as #{existing.template_id} (v#{existing.version})")
  end

  return unless (template = parse_upload(content))

  superseding = Template.active.find_by(template_id: template.template_id)
  template.version = Template.next_version(superseding.version) if superseding

  if template.save
    superseding&.supersede!

    respond_to do |format|
      format.turbo_stream do
        streams = [ turbo_stream.append("catalog", partial: "templates/template", locals: { template: template }) ]
        streams << turbo_stream.remove("empty_notice") unless superseding
        streams << turbo_stream.remove(dom_id(superseding)) if superseding
        render turbo_stream: streams
      end
      format.json { render json: { template_id: template.template_id, version: template.version, name: template.web_template["concept"] }, status: :created }
    end
  else
    render_upload_error(template.errors.full_messages.join(", "))
  end
end
```

サービスオブジェクトやイベント機構（`ActiveSupport::Notifications`等）は存在しない。`Template`モデル
本体（全84行）にも `after_create` 等のコールバック定義は無く、親クラス `ApplicationRecord` も
`primary_abstract_class` の1行のみ（[app/models/application_record.rb:1-3](../../app/models/application_record.rb#L1-L3)）。
gem側（openehr-rails）にもテンプレート登録イベントのフックは無い（1.7節参照）。
**したがって、パスカード抽出器を差し込む候補位置は `TemplatesController#create` の74行目
（`superseding&.supersede!` の後、`respond_to` の前）が唯一の自然な位置となる**（コールバック機構が
無いため、`Template`モデルに `after_create` を新設するのがWP2での選択肢の一つになる）。

checksum一致時（64-66行）は早期リターンし `save` に到達しないため、re-drop時の再抽出は別途考慮が必要。

### 1.4 動的フォーム生成・検証・保存・FHIR R5ファサード

- **フォーム生成**: `FormsController#show` が登録済み `web_template` をリクエスト時に解釈する
  （コード生成なし）（[app/controllers/forms_controller.rb:1-10](../../app/controllers/forms_controller.rb#L1-L10)）：

  ```ruby
  class FormsController < ApplicationController
    # Renders a working form for a registered template by interpreting its
    # web_template at request time -- no code generation, no per-template
    # controller/view.
    def show
      @template = Template.active.find_by!(template_id: params[:template_id])
  ```

  `_field.html.erb` は `field["rm_type"]`（DV_QUANTITY/DV_CODED_TEXT/その他）で入力タイプを分岐する
  （[app/views/templates/_field.html.erb:9-28](../../app/views/templates/_field.html.erb#L9-L28)、行内容は未引用・要目視確認）。

- **検証・保存**: `CompositionsController#create` が `Opt::FormValidator` → `Opt::CompositionBuilder#build`
  → `OpenEHR::Serializer::RMJSONSerializer` の順に処理し、`compositions.rm_composition`（JSON）に保存する
  （[app/controllers/compositions_controller.rb:10-26](../../app/controllers/compositions_controller.rb#L10-L26)）：

  ```ruby
  def create
    @template = Template.active.find_by!(template_id: params[:template_id])
    values = (params[:values] || {}).to_unsafe_h

    result = Opt::FormValidator.call(@template, values)
    unless result.valid?
      @values = values
      @errors = result.errors
      return render "forms/show", status: :unprocessable_content
    end

    rm_composition = Opt::CompositionBuilder.new(@template, values).build
    json = OpenEHR::Serializer::RMJSONSerializer.new(rm_composition).serialize

    composition = @template.compositions.create!(rm_composition: JSON.parse(json))
    redirect_to composition_path(composition), notice: "登録しました"
  end
  ```

- **FHIR R5ファサード**（Phase 3コミット `9f5ef95`）: `Fhir::ProfilesController` が登録済み各Templateの
  `source_xml` を再パースし `OpenehrRails::Fhir::ProfileGenerator` でStructureDefinitionをオンザフライ生成する
  （[app/controllers/fhir/profiles_controller.rb:24-29](../../app/controllers/fhir/profiles_controller.rb#L24-L29)）：

  ```ruby
  def all_profiles
    Template.active.flat_map do |template|
      opt = OpenehrRails::Opt.parse(template.source_xml)
      OpenehrRails::Fhir::ProfileGenerator.new(opt).profiles
    end
  end
  ```

  ルートは `GET fhir/r5/StructureDefinition/:id`（[config/routes.rb:24-25](../../config/routes.rb#L24-L25)）。
  フルFHIR RESTファサードはスコープ外とコメントに明記（同コントローラ6-8行）。

- **ポリモーフィックな受け皿**（Phase 3コミット `3ecc2d2`）: `TemplatesController#preview` が
  `.adl` → `preview_adl`、`"_type":"COMPOSITION"`のJSON → `preview_composition`、それ以外はOPTとして
  分岐する（[app/controllers/templates_controller.rb:28-41](../../app/controllers/templates_controller.rb#L28-L41)）：

  ```ruby
  def preview
    file = params[:file]
    return preview_adl(file) if file && file.original_filename.to_s.match?(/\.adl\z/i)

    content = read_validated_content || return
    return preview_composition(content) if composition_json?(content)

    return unless (@template = parse_upload(content))
  ```

### 1.5 DB構成（PostgreSQL/pgvector導入可否）

全環境SQLite3アダプタ（[config/database.yml:7-19](../../config/database.yml#L7-L19)）：

```yaml
default: &default
  adapter: sqlite3
  max_connections: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000

development:
  <<: *default
  database: storage/development.sqlite3

test:
  <<: *default
  database: storage/test.sqlite3
```

本番は primary/cache/queue/cable の4DB構成（[config/database.yml:20-33](../../config/database.yml#L20-L33)、
solid_cache/solid_queue/solid_cable用）。

`Gemfile` / `Gemfile.lock` / `config/` を `grep -rniE 'pg|postgres|pgvector|vector'` した結果、ヒットは
`config/credentials.yml.enc` の暗号化Base64文字列1件のみ（偽陽性、復号は未実施のため中身は不明）。
DBドライバは `sqlite3 (2.9.6)` のみ（[Gemfile.lock:372-377](../../Gemfile.lock#L372-L377)）。
Dockerfileも `apt-get install ... sqlite3`（PostgreSQLクライアント無し、[Dockerfile:11-19](../../Dockerfile#L11-L19)）、
`config/deploy.yml`（Kamal）にもDBアクセサリは無くsqliteファイル用の永続ボリュームのみ
（[config/deploy.yml:68-72](../../config/deploy.yml#L68-72)、mysql/valkeyアクセサリはコメントアウト済み）。

**pgvector導入の可否**: 現構成では不可（PostgreSQL自体が使われていない）。PostgreSQLへ移行した場合の
障害（solid_cache/solid_queue/solid_cable のSQLite依存範囲、本番4DB構成の移行要否）は本WP0の範囲では
未調査。→ 5節「承認が必要な判断」参照。

### 1.6 Ruby/Railsバージョン

- Ruby: `4.0.6`（[.ruby-version:1](../../.ruby-version#L1)）。Dockerfileも同じ
  `ARG RUBY_VERSION=4.0.6`（[Dockerfile:11](../../Dockerfile#L11)）。`Gemfile.lock`に`RUBY VERSION`
  セクションは無い（grep不検出、不明）
- Rails: `Gemfile`で `"~> 8.1.3", ">= 8.1.3.1"` 指定、`Gemfile.lock`で `rails (8.1.3.1)` に解決
  （[Gemfile:4](../../Gemfile#L4)、[Gemfile.lock:254](../../Gemfile.lock#L254)）
- `rspec-rails (8.0.4)`（[Gemfile.lock:307](../../Gemfile.lock#L307)）
- `openehr (2.3.0)` / `openehr-rails (0.4.0)`、後者はローカルpath gem
  （[Gemfile.lock:217,538](../../Gemfile.lock#L217)、[Gemfile:65](../../Gemfile#L65) `gem "openehr-rails", path: "/home/skoba/src/openehr-rails"`）

### 1.7 テスト環境（RSpec導入状況・spec構成・実行方法）

`.rspec` は1行のみ（[.rspec:1](../../.rspec#L1)）: `--require spec_helper`

`spec/spec_helper.rb`（rspec:install生成のデフォルトそのまま、推奨設定はコメントアウト、全94行）の
有効設定（[spec/spec_helper.rb:16-45](../../spec/spec_helper.rb#L16-L45)、中間コメント省略）:

```ruby
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups
```

`spec/rails_helper.rb`（全79行）は `rspec/rails` と `capybara/rspec` をrequireし、
`Capybara.javascript_driver = :selenium_chrome_headless` を設定。fixture_pathsは`spec/fixtures`、
`use_transactional_fixtures = true`、systemスペックはデフォルト`rack_test`で`js: true`指定時のみ
ヘッドレスブラウザに切替（[spec/rails_helper.rb:10-12,41-43,48,77-78](../../spec/rails_helper.rb#L10-L12)）。

spec配下は13ファイル・5ディレクトリ構成
（`spec/{fixtures/{adl,opt}, lib/opt, models, requests, system}`）:

```
spec/lib/opt/composition_reader_spec.rb
spec/lib/opt/form_validator_spec.rb
spec/lib/opt/template_diff_spec.rb
spec/models/template_spec.rb
spec/requests/compositions_spec.rb
spec/requests/fhir_profiles_spec.rb
spec/requests/polymorphic_drop_spec.rb
spec/requests/templates_spec.rb
spec/system/forms_spec.rb
spec/system/multi_file_dropzone_spec.rb
spec/system/opt_dropzone_spec.rb
spec/system/polymorphic_dropzone_spec.rb
spec/system/url_dropzone_spec.rb
```

fixtureは2件のみ: `spec/fixtures/opt/patient_blood_pressure.opt`（Ocean Template Designer 2.6.1214Beta
生成、[spec/fixtures/opt/patient_blood_pressure.opt:1-3](../../spec/fixtures/opt/patient_blood_pressure.opt#L1-L3)）と
`spec/fixtures/adl/openEHR-EHR-CLUSTER.exam-uterine_cervix.v1.adl`。OPT内のアーキタイプIDは
`openEHR-EHR-COMPOSITION.encounter.v1` / `openEHR-EHR-OBSERVATION.blood_pressure.v1` /
`openEHR-EHR-OBSERVATION.heart_rate-pulse.v1`（grep実測。CKM実在照合はネットワーク未使用のため未実施）。
言語は `en`（`/template/language/code_string`、5-9行目実測: `<code_string>en</code_string>`）。
**日本語OPT fixtureはAnlage・openehr-rails両リポジトリに0件**。

**RSpecの正式な実行コマンドはリポジトリ内のどこにも記載が無い**。根拠:
- `bin/` 配下に rspec バインスタブが無い（実測: `brakeman, bundler-audit, ci, dev, docker-entrypoint,
  importmap, jobs, kamal, rails, rake, rubocop, setup, thrust`）
- `bin/ci`（`config/ci.rb`実行）のステップにRSpec実行が無い
  （[config/ci.rb:3-10](../../config/ci.rb#L3-L10): Setup / RuboCop / bundler-audit / importmap audit / brakeman のみ）
- `.github/workflows/ci.yml` の3ジョブ（scan_ruby / scan_js / lint）にもRSpec実行ジョブが無い
  （[.github/workflows/ci.yml:8-66](../../.github/workflows/ci.yml#L8-L66)）
- `Rakefile` はRailsデフォルト（`load_tasks`のみ）
- `CLAUDE.md:18` にTDD方針の記載はあるが実行コマンドの明記は無い

→ 「不明」。慣例的には `bundle exec rspec` だがリポジトリ内の裏付けが無いため、WP2着手前に
実行して確認するか、5節の「承認が必要な判断」で確定する必要がある。

その他: `app/templates/operational` ディレクトリは存在するが空
（[config/initializers/openehr.rb:3-5](../../config/initializers/openehr.rb#L3-L5)のコメントで
`rails g openehr:scaffold` によるコピー先と説明されているが、実ファイルは無い）。`storage/`には
`test.sqlite3`/`development.sqlite3`/`.keep`のみ。Active Storageはengineとして読み込まれているが
（[config/application.rb:8](../../config/application.rb#L8)）、`db/schema.rb`にactive_storage_*テーブルは
無く、`app/`に`has_one_attached`等の使用箇所も無い（grep不検出）。**OPT本体はActive Storageを介さず
`templates.source_xml`にDB直接保存**される。

`docs/`配下の実在ファイルは `docs/upstream-candidates.md` と `docs/plans/opt-dropzone.md` のみ。
`docs/design/`（本ファイルが最初の設置）と `docs/ideas-2027.md` はCLAUDE.mdから参照されるが、
このWP0時点では未作成だった（`ls`でNo such file or directoryを確認済み）。

---

## 2. openehr-ruby / openehr-rails のOPTパーサ露出情報の棚卸し

### 2.1 パーサの入口とオブジェクトモデル

OPTパーサの入口は `OpenEHR::Parser::OPTParser`（`Parser::Base`を継承し、`XMLConstraintParsing` /
`XMLPrimitiveParsing` / `XMLDomainTypeParsing` の3モジュールをinclude）
（[.../openehr-2.3.0/lib/openehr/parser/opt_parser.rb:8-11](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/opt_parser.rb#L8-L11)）：

```ruby
class OPTParser < ::OpenEHR::Parser::Base
  include XMLConstraintParsing
  include XMLPrimitiveParsing
  include XMLDomainTypeParsing
```

Anlageが実際に呼ぶのはこのサブクラス `OpenehrRails::Opt::Parser`（openehr-rails gem、生のXML文字列も
受け付けるよう`#parse`をオーバーライド）（[openehr-rails/lib/openehr_rails/opt/parser.rb:11-21](file:///home/skoba/src/openehr-rails/lib/openehr_rails/opt/parser.rb#L11-L21)）：

```ruby
class Parser < OpenEHR::Parser::OPTParser
  UTF8_BOM = "\xEF\xBB\xBF".freeze

  def parse
    source = if raw_xml_content?(@filename)
               @filename # raw OPT XML content
             else
               File.open(@filename)
             end
    @opt = Nokogiri::XML::Document.parse(source)
    @opt.remove_namespaces!
```

`#parse`はNokogiriでXMLを読み `OpenEHR::AM::Template::OperationalTemplate` を返す
（[opt_parser.rb:42-63](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/opt_parser.rb#L42-L63)）：

```ruby
def parse
  @opt = Nokogiri::XML::Document.parse(File.open(@filename))
  @opt.remove_namespaces!

  uid = build_uid
  defs = definition

  OpenEHR::AM::Template::OperationalTemplate.new(
    uid: uid,
    concept: concept,
    original_language: language,
    description: description,
    template_id: template_id,
    archetype_id: template_id,  # Use template_id as archetype_id for compatibility
    definition: defs,
    ontology: (@component_terminologies || {})[defs.archetype_id.value] || create_template_ontology,
    component_terminologies: @component_terminologies || {},
    terminology_extracts: @component_terminologies || {},
    adl_version: "1.4"
  )
end
```

`OperationalTemplate` は `Archetype` を継承し、`component_terminologies` / `terminology_extracts` /
`template_id` を追加で露出する
（[am/template.rb:10-11](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/am/template.rb#L10-L11)）。
親 `Archetype` は `archetype_id` / `concept` / `definition` / `ontology` を露出する
（[am/archetype.rb:11-14](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/am/archetype.rb#L11-L14)）。

制約モデルの木構造: `CObject`（`rm_type_name`/`node_id`/`occurrences`を露出、
[archetype/constraint_model.rb:95-96](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/am/archetype/constraint_model.rb#L95-L96)）
→ `CComplexObject`（`attributes`を露出、同288-289行）/ `CPrimitiveObject`、
`CAttribute`（`children`を露出、[同176-177行](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/am/archetype/constraint_model.rb#L176-L177)）。

### 2.2 ノード列挙手段

`Archetype#physical_paths` が `each_constraint_node`（private、attributes/childrenを再帰）で
深さ優先に全ノードのパスを収集する
（[am/archetype.rb:128-163](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/am/archetype.rb#L128-L163)）：

```ruby
def physical_paths
  paths = []
  each_constraint_node(definition) { |node| paths << node.path if node.respond_to?(:path) }
  paths.uniq
end

private

def each_constraint_node(node, &block)
  return if node.nil?

  yield node
  if node.respond_to?(:attributes) && node.attributes
    node.attributes.each { |attribute| each_constraint_node(attribute, &block) }
  end
  return unless node.respond_to?(:children) && node.children

  node.children.each { |child| each_constraint_node(child, &block) }
end
```

`physical_paths`は`path`しか返さない（ノードオブジェクト自体は返らない）。パスカード抽出器を書く際は
`each_constraint_node`相当のprivateロジックを自前で再実装するか、`collect`（同165-169行、privateかつ
klassフィルタ専用）の使い方を確認する必要がある。→ 4節の欠落項目参照。

### 2.3 アーキタイプパス

パース時にNodeクラス（`opt_parser.rb`末尾、トップレベル定義）でパスを構築する
（[opt_parser.rb:185-197](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/opt_parser.rb#L185-L197)）：

```ruby
class Node
  attr_accessor :id, :path
  attr_reader :parent

  def initialize(parent = nil)
    @parent = parent
    @path = '/' if parent.nil?
  end

  def root?
    parent.nil?
  end
end
```

`c_complex_object`はnode_idがあれば親パスに`[atNNNN]`を連結する
（[xml_constraint_parsing.rb:31-39](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/xml_constraint_parsing.rb#L31-L39)）：

```ruby
def c_complex_object(xml, node)
  rm_type_name = xml.xpath('./rm_type_name').text
  node_id = xml.xpath('./node_id').text
  unless node_id.nil? or node_id.empty?
    node.id = node_id
    node.path = "#{node.path}[#{node.id}]"
  end
  OpenEHR::AM::Archetype::ConstraintModel::CComplexObject.new(rm_type_name: rm_type_name, node_id: node.id, path: node.path, occurrences: occurrences(xml.xpath('./occurrences')), attributes: attributes(xml.xpath('./attributes'), node))
end
```

属性パスは`attributes()`が`"/rm_attribute_name"`形式で連結する
（[xml_constraint_parsing.rb:41-54](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/xml_constraint_parsing.rb#L41-L54)）。
各ノードのパスは`ArchetypeConstraint#path`（`@path || calculate_path`、
[constraint_model.rb:126-128](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/am/archetype/constraint_model.rb#L126-L128)）で取得できる。

`Archetype#logical_paths(a_lang)`は`physical_paths`の`[atNNNN]`述語を指定言語のterm textに置換する
（[archetype.rb:107-109](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/am/archetype.rb#L107-L109)）が、
内部で`ontology.term_definition`を呼ぶため2.5節の型不整合の疑いが波及する（未検証）。

### 2.4 at-code・RM型・occurrences

`node_id`（at-code）は`CObject#node_id`で取得、XMLの`./node_id`要素から設定される
（[constraint_model.rb:112-117](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/am/archetype/constraint_model.rb#L112-L117)）。
`rm_type_name`は各CObjectの`attr_reader`で取得、XMLの`./rm_type_name`テキストから設定される
（[constraint_model.rb:105-110](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/am/archetype/constraint_model.rb#L105-L110)）。
`occurrences`は`CObject#occurrences`（型は`OpenEHR::AssumedLibraryTypes::Interval`、
`lower`/`upper`属性を持つ、[assumed_library_types.rb:11-12](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/assumed_library_types.rb#L11-L12)）
で取得でき、`occurrences()`/`numeric_interval()`（[xml_constraint_parsing.rb:101-147](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/xml_constraint_parsing.rb#L101-L147)）
がXML要素から構築する。

### 2.5 言語別ラベル・説明【最重要：日本語の取得可否】

**OPTParserの`term_definitions`はテンプレート原語1言語キーのみを構築し、`language`属性は一切読まない**
（[opt_parser.rb:159-168](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/opt_parser.rb#L159-L168)）：

```ruby
def term_definitions(nodes)
  term_definitions = nodes.xpath 'term_definitions'
  term_items = term_definitions.map do |term|
    code = term.attributes['code'].value
    text = term.at('items[@id="text"]').text
    description = term.at('items[@id="description"]').text
    OpenEHR::AM::Archetype::Terminology::ArchetypeTerm.new(code: code, items: {'text' => text, 'description' => description})
  end
  { language.code_string => term_items }
end
```

言語キーは`/template/language/code_string`（テンプレート原語）で決まる
（[opt_parser.rb:87-89](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/opt_parser.rb#L87-L89)）：

```ruby
def language
  @language ||= OpenEHR::RM::DataTypes::Text::CodePhrase.new(code_string: text_on_path(@opt, TEMPLATE_LANGUAGE_CODE_PATH), terminology_id: OpenEHR::RM::Support::Identification::TerminologyID.new(value: text_on_path(@opt,TEMPLATE_LANGUAGE_TERM_ID_PATH)))
end
```

実OPT fixture（`spec/fixtures/opt/patient_blood_pressure.opt`）で実測すると、`<term_definitions>`要素
自体は123箇所存在するが、`code`属性のみを持ち`language`属性は持たない（実測: `<term_definitions
code="at0.10">`等、`language=`属性なし）。テンプレート原語は`en`（同fixture 5-9行目）。
**日本語ラベルが取得できるのは「OPT原語がjaの場合」のみで、多言語同時保持のコードパスは存在しない**。

openehr-rails側の`FieldExtractor#term_text`にも言語指定引数は無く、全言語横断（`each_value`）で
最初に一致したものを返す（[openehr-rails/lib/openehr_rails/opt/field_extractor.rb:258-267](file:///home/skoba/src/openehr-rails/lib/openehr_rails/opt/field_extractor.rb#L258-L267)）：

```ruby
def term_text(archetype_id, code)
  terminology = @template.component_terminologies[archetype_id]
  return nil unless terminology

  terminology.term_definitions.each_value do |terms|
    term = terms.find { |t| t.code == code }
    return term.items['text'] if term
  end
  nil
end
```

同ファイル11行目のコメントも「label: display text from the template terminology (any language)」と
明記している。scaffoldジェネレータのi18nロケールファイルも`original_language`のコードで1ファイルのみ
生成され（[scaffold_generator.rb:168-170](file:///home/skoba/src/openehr-rails/lib/generators/openehr/scaffold/scaffold_generator.rb#L168-L170)）、多言語同時生成は無い。**日本語OPT fixtureが両リポジトリに1件も
存在しないため、日本語での実動作は未検証**（unknowns参照）。

### 2.6 データ型制約

**DV_QUANTITY**（単位・値域・精度）: `c_dv_quantity`が`property`・`list`（`CQuantityItem`配列）・
`assumed_value`を読む（[xml_domain_type_parsing.rb:44-60](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/xml_domain_type_parsing.rb#L44-L60)）：

```ruby
def c_dv_quantity(attr_xml, node)
  rm_type_name = attr_xml.at('rm_type_name').text
  occurrences = occurrences(attr_xml.at('occurrences'))
  property = property_code_phrase(attr_xml.at('property'))
  list = attr_xml.xpath('.//list').map { |element| c_quantity_item(element) }
  assumed_value = dv_quantity_assumed_value(attr_xml.at('assumed_value'))
  OpenEHR::AM::OpenEHRProfile::DataTypes::Quantity::CDvQuantity.new(
    rm_type_name: rm_type_name, occurrences: occurrences, list: list, property: property, assumed_value: assumed_value
  )
end

def c_quantity_item(element)
  units = element.at('units').text if element.at('units')
  magnitude = numeric_interval(element.at('magnitude'), real: true) if element.at('magnitude')
  precision = numeric_interval(element.at('precision'), real: false) if element.at('precision')
  OpenEHR::AM::OpenEHRProfile::DataTypes::Quantity::CQuantityItem.new(magnitude: magnitude, precision: precision, units: units)
end
```

`CQuantityItem`は`magnitude`/`precision`/`units`を露出する
（[openehr_profile/data_types/quantity.rb:102-104](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/am/openehr_profile/data_types/quantity.rb#L102-L104)）。

**値集合**（DV_CODED_TEXT）: `c_code_phrase`が`C_CODE_PHRASE`要素から`terminology_id`と`code_list`
（文字列配列）を読む（[xml_domain_type_parsing.rb:13-31](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/xml_domain_type_parsing.rb#L13-L31)）。

**ORDINAL/SCALE**: `c_dv_ordinal`が`list`（`DvOrdinal`配列: `value`整数 + `symbol`=`DvCodedText`）を
構築する（[xml_domain_type_parsing.rb:75-80](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/xml_domain_type_parsing.rb#L75-L80)）：

```ruby
def c_dv_ordinal(attr_xml, node)
  rm_type_name = attr_xml.at('rm_type_name').text
  occurrences = occurrences(attr_xml.at('occurrences'))
  list = attr_xml.xpath('list').map { |element| dv_ordinal_item(element) }.compact
  OpenEHR::AM::OpenEHRProfile::DataTypes::Quantity::CDvOrdinal.new(rm_type_name: rm_type_name, occurrences: occurrences, list: list)
end
```

`dv_ordinal_item`は同ファイル86-95行。**C_DV_STATEは未サポートでNotImplementedErrorを投げる**
（同123-125行）。

**日付系**（C_DATE/C_DATE_TIME/C_TIME）: `pattern`または`range`（Interval）を持つ
（[xml_primitive_parsing.rb:13-23](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/xml_primitive_parsing.rb#L13-L23)）。C_PRIMITIVE系は`CPrimitiveObject`に包まれ、`method_missing`で
`item`へ委譲される（[constraint_model.rb:279-285](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/am/archetype/constraint_model.rb#L279-L285)）。

### 2.7 用語バインディング

**OPTParserは`term_bindings`を一切読まない**。`opt_parser.rb`全体に文字列`term_bindings`は出現しない
（grep確認済み）。`archetype_terminology`が構築する`ArchetypeTerminology`には`concept_code` /
`original_language` / `term_definitions`のみが渡される
（[opt_parser.rb:149-157](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/opt_parser.rb#L149-L157)）：

```ruby
def archetype_terminology(nodes)
  td = term_definitions(nodes)
  concept_code = td[language.code_string][0]
  OpenEHR::AM::Archetype::Terminology::
    ArchetypeTerminology.new(
          concept_code: concept_code,
          original_language: language,
          term_definitions: td)
end
```

`ArchetypeOntology`側の受け皿（`attr_accessor :term_bindings`、
[am/archetype/ontology.rb:8](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/am/archetype/ontology.rb#L8)）は存在するが、
OPT経路では埋められないため常に`nil`のまま。参考: 非OPTの`XMLArchetypeParser`（ADL/XMLアーキタイプ
パーサ）は`term_bindings`を読むコードを持つ
（`xml_archetype_parser.rb:187`: `term_bindings: ontology_bindings(node, 'term_bindings') { |value|
[code_phrase_from_binding(value)] }`）が、この経路はAnlageのOPT取り込みフローには接続されていない。

**この欠落は実データで裏付けられる**。実OPT fixture `spec/fixtures/opt/patient_blood_pressure.opt`には
SNOMED-CTの`term_bindings`要素が4箇所実在する（例、712-720行）：

```xml
<term_bindings terminology="SNOMED-CT">
  <items code="at0.23">
    <value>
      <terminology_id>
        <value>SNOMED-CT(2009)</value>
      </terminology_id>
      <code_string>64730000</code_string>
    </value>
  </items>
```

（もう1箇所は1408-1416行、code="at0000"→`163020007`。terminology="SNOMED-CT"は2箇所とも別の
`term_bindings`ブロックで、grep実測では`term_bindings`の文字列は当該fixture中に4回出現。）

**つまり、OPT XML自体にはterminologyバインディングデータが含まれているが、openehr gemの
OPTParserがそれを読み捨てている。** パスカードの`bindings`欄をOPT単独の取得手段で満たすことは
できない（対応方針は5節参照）。

### 2.8 テンプレートID・provenance

テンプレートIDは`OPTParser#template_id`が`/template/template_id/value`から構築する
（[opt_parser.rb:70-74](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/opt_parser.rb#L70-L74)）。
埋め込みアーキタイプIDは`CArchetypeRoot#archetype_id`で取得でき、テンプレート全体では
`OperationalTemplate#referenced_archetype_ids`（`component_terminologies`のキー）でも列挙できる
（[am/template.rb:77-85](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/am/template.rb#L77-L85)）。

テンプレートレベルのprovenanceは取得可能: `#parse`が`uid`と`description`
（`/template/description`配下の`original_author`/`purpose`/`keywords`/`use`/`misuse`/`copyright`/
`other_details`から構築、[opt_parser.rb:91-113](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/parser/opt_parser.rb#L91-L113)）を`OperationalTemplate`に渡す。
親`AuthoredResource`が`description`を`attr_accessor`で露出するため読み出せる
（[rm/common/resource.rb:6-8](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/rm/common/resource.rb#L6-L8)）。ただし**埋め込みアーキタイプ単位のprovenance**
（各アーキタイプの原作者・CKM URL）の取得手段は未確認。

### 2.9 openehr-rails FieldExtractorが露出する情報

`Opt::FieldExtractor`は`#entries`（ENTRY単位）と`#fields`（全ELEMENTのフラットなHash列）を露出する
（[field_extractor.rb:50-61](file:///home/skoba/src/openehr-rails/lib/openehr_rails/opt/field_extractor.rb#L50-L61)）。各fieldは
`name`/`label`/`path`/`rm_type`/`node_id`/`archetype_id`/`entry_rm_type`/`column_type`/`required`を
持ち、型別制約がmergeされる（[field_extractor.rb:151-165](file:///home/skoba/src/openehr-rails/lib/openehr_rails/opt/field_extractor.rb#L151-L165)）。

**ELEMENT降下範囲の制約**: `DESCENDABLE_ATTRIBUTES = %w[data events items value].freeze`
（[field_extractor.rb:43-44](file:///home/skoba/src/openehr-rails/lib/openehr_rails/opt/field_extractor.rb#L43-L44)、コメント
「ELEMENT containers we descend into; protocol/state are skipped for now.」）。
**protocol/state配下のELEMENTはFieldExtractorの対象外**。全ノード列挙自体は
`Archetype#physical_paths`/`each_constraint_node`（2.2節）で可能だが、そこからcapture属性
（フォーム入力型等）への変換器はELEMENT限定のFieldExtractor以外に存在しない。

---

## 3. パスカード必須ブロック別の充足マトリクス

| ブロック | 取得手段 | 状態 |
|---|---|---|
| identity（template_id/archetype_id/path/at_code） | 2.3, 2.4, 2.8節 | ○ 揃っている |
| semantics.rm_type | 2.4節 | ○ 揃っている |
| semantics.labels/descriptions（言語別・日本語優先） | 2.5節 | △ 原語1言語のみ取得可。多言語同時保持・言語指定取得は不可（欠落） |
| constraints.occurrences | 2.4節 | △ 取得可能だが欠損時の挙動は未検証（3.1未確認事項） |
| constraints（quantity単位・値域・精度、code_list、ordinal/scale、日付pattern/range） | 2.6節 | ○ 揃っている（C_DV_STATEのみ非対応） |
| bindings（用語バインディング三つ組） | 2.7節 | × OPT経路では常に空。実データはXMLに存在するがパーサが読まない（欠落） |
| capture（帳票正規化規則の構造） | 2.9節 | △ ELEMENT（data/events/items/value配下）のみ。protocol/state配下は対象外（欠落） |
| provenance（抽出元OPT・抽出日時・抽出器バージョン） | 1.1, 2.8節 | ○ テンプレートレベルは揃っている。取り込み元URL（CKM）はDB非保存（欠落） |
| reserved（voice_aliases等） | — | 対象外（WP1で空枠として定義するのみ） |

---

## 4. 未確認事項

1. RSpecの正式な実行コマンド（1.7節。bin/・CI・Rakefileのいずれにも記載なし）
2. OPT産の`ArchetypeTerminology`に対し`ArchetypeOntology#term_definition(lang:, code:)`が実際に
   動作するか。コード上、OPTParserが構築する`term_definitions`の値は`ArchetypeTerm`の配列
   （2.5節）である一方、`term_definition`は`@term_definitions[args[:lang]][args[:code]]`という
   2段Hashインデックスを前提とする（[am/archetype/ontology.rb:70-76](file:///home/skoba/.rbenv/versions/4.0.6/lib/ruby/gems/4.0.0/gems/openehr-2.3.0/lib/openehr/am/archetype/ontology.rb#L70-L76)）。
   `Array#[](Stringコード)`となり`TypeError`になる可能性があるが実行未検証（`logical_paths`も
   内部で`term_text`→`term_definition`を呼ぶため波及する）
3. OPT XMLで子ノードのoccurrences要素が完全に欠けている場合の挙動（`numeric_interval`がnilを返し
   `CObject#occurrences=`が`ArgumentError('invaild occurrences')`を投げる可能性があるが実データでの
   検証は未実施）
4. `spec/fixtures/opt/patient_blood_pressure.opt`内のアーキタイプID（`encounter.v1`等）がCKMに
   実在するかのオンライン照合（ネットワーク未使用のため未実施。ID形式とOcean Template Designer
   生成コメントまでは確認済み）
5. `config/credentials.yml.enc`の中身（復号していないため、PostgreSQL関連設定が含まれるか否かは
   厳密には不明。平文設定ファイル・Gemfile・lockfileにはpg/pgvectorの痕跡は皆無）
6. `openehr_templates`テーブルに実データが入っているか（`storage/development.sqlite3`の中身は未読）
7. mountされた`OpenehrRails::Engine`（`/openehr`配下）がどのルート・画面を提供するか（gem側UIは
   本WP0の対象外）
8. `openehr`gem（`~> 2.3`）側`OPTParser`/`ADLParser`の親クラス（`build_uid`, `concept`等）の実装詳細
9. 日本語ラベルの実動作（日本語`original_language`のOPTでの実例）。日本語OPT fixtureが両リポジトリに
   存在しないため、ソースコード上の設計（原語キー1つがそのまま通る）は確認できたが、実データでの
   検証はできていない
10. `spec/templates/sample_blood_pressure.opt`（openehr-rails gem側fixture）を参照するspecが
    見つからなかった。現在の用途は不明

---

## 5. 承認が必要な判断

1. **WP3のpgvector前提とAnlage現行DB構成の矛盾**: WP3は「pgvectorによる埋め込み索引」「Rails＋
   PostgreSQL内で完結」を前提とするが、Anlageは全環境SQLite3（1.5節）。PostgreSQLへの移行方針
   （いつ・どのDB（primary/cache/queue/cable全部か一部か）・移行コスト）を人間の判断で確定して
   いただきたい
   → **決定（2026-08-22 人間回答）**: WP3計画提示時に移行範囲・手順・コストの材料付きで決める。WP1/WP2はSQLiteのまま進行
2. **RSpec実行方法の確定**: リポジトリ内に実行コマンドの記載が無い（1.7節、4節-1）。WP2以降の
   TDDサイクルの前提となるため、正式なコマンド（`bundle exec rspec`等）を確認・確定し、
   CLAUDE.mdの「ビルド・テストコマンド」節（現在「未記載」）に追記してよいか承認いただきたい
   → **決定（2026-08-22 人間承認）**: `bundle exec rspec <path>` を追記済み（同セッションで実行実証）
3. **bindings欠落への対応方針**: OPTParser（gem側）がterm_bindingsを読まないことはコード上確定
   しており（2.7節）、かつ実データ（fixture内SNOMED-CTバインディング）で裏付け済み。gem自体の
   拡張は層規律（CLAUDE.md規律5）に抵触するため本リポジトリでは行えない。一方Anlageは
   `templates.source_xml`にOPT原文を保持している（1.1節）ため、Anlage側でOPT XMLを独自に
   再解析してterm_bindingsを補完抽出する余地はある。この方針（Anlage側補完 or
   `docs/upstream-candidates.md`へのgem改善提案の記録に留める）のどちらを取るか、判断を
   仰ぎたい
   → **決定（2026-08-22 人間回答）**: Anlage側で補完抽出する（source_xml再解析でterm_bindings/referenceSetUri両形式を取得）。gem改善は`docs/upstream-candidates.md` 6項に記録済み。なお同日、C_CODE_REFERENCE（referenceSetUri）を含むOPTはgemパーサで**パース自体が失敗**することも実OPTで判明（同6項）
4. **WP1用サンプルOPTの入手**: WP1のサンプルカード3枚の指定素材のうち、手元の実OPTでは
   `openEHR-EHR-OBSERVATION.blood_pressure.v1`（fixtureにあるのは**v1**）のみで、プロンプトが
   指定する`v2`のat0004は手元に無い。また`problem_diagnosis`系・`laboratory_test_result`系の
   実OPTも手元に存在しない（1.7節）。日本語OPT（2.5節、2.9節）も0件。これらをArchetype Designer
   経由で人間に作成・入手依頼してよいか確認したい
   → **決定・解消（2026-08-22）**: 3点入手済み（CardiologyEncounter / ProblemList / LabResultReport、いずれもlang=ja、`spec/fixtures/opt/`）。検収記録は `pathcards-language-policy.md` 5節。カード2素材の単位・基準範囲のみAD追加待ち（WP1は暫定素材で着手）

---

## 6. WP1に向けた所見

- **bindings空許容の設計は妥当、かつ根拠がある**: プロンプトのWP1スキーマ案は`bindings`配列の
  空許容を明記しているが、本調査で「OPT単独では常に空になる」ことが実データで実証された
  （2.7節）。WP1のスキーマ設計文書には、この欠落が実装上の制約であって設計判断ではないことを
  明記するとよい
- **capture構造のみ定義（値は空）という設計方針も同様に妥当**: `FieldExtractor`がprotocol/state
  配下を対象外としている（2.9節）ため、captureの初期値を空にする設計はこの制約と整合する
- **semantics.labelsの多言語表現は「取得できる分だけ」の設計にすべき**: パーサが単一言語しか
  返さない以上、スキーマの`labels`はテンプレート原語1件から始まり、将来的な多言語拡張は
  Anlage側でのterm_definitions再解析（gemを経由しない独自パース）が必要になる可能性が高い
- **provenance設計の素材**: テンプレートレベルの`description`（original_author/purpose等、
  2.8節）は取得できるので、WP1のprovenanceブロックにこれらのフィールドを含める価値がある。
  一方CKM取り込み元URLはAnlage側で未保存（1.1節）のため、WP1設計時点では「取得元URL」欄は
  空欄前提にするか、テンプレート登録処理自体の拡張（`templates`テーブルへの`source_url`列追加）
  を別途検討課題として記録するとよい
- **WP1のサンプルカード3枚は実OPT入手が前提条件**: 5節-4の通り、v2血圧・傷病名・検査値の
  実OPTが手元にない。WP1着手前にこれらの入手（またはArchetype Designerでの作成）が必要
- **フック位置の実装方針はWP2計画で確定させる**: 1.3節の通り、コールバック機構が存在しないため
  `TemplatesController#create`への直接追記か`Template`モデルへの`after_create`新設かの選択が
  必要。WP2計画提示時にテストTODOリストと合わせて判断材料を示すとよい

---

**本レポートはWP0（探索）の成果物であり、コード変更は一切行っていない。承認をお待ちする。**
