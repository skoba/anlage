# 定義の層（docs/design/definition-layer-plan.md、skoba/anlage#257）
namespace :definitions do
  desc "Lint a definition bundle directory (DIR=path; FORMAT=json for machine-readable output). Exits 1 when there are errors (drafts alone exit 0)"
  task lint: :environment do
    dir = ENV["DIR"].to_s
    abort "使い方: bin/rails definitions:lint DIR=<定義の組のディレクトリ（bundle.yml のあるところ）> [FORMAT=json]" if dir.empty?

    report = Definitions::Linter.call(dir)
    if ENV["FORMAT"] == "json"
      puts JSON.pretty_generate(ok: report.ok?, problems: report.problems.map(&:to_h))
    else
      puts "定義の組 #{dir}: エラー #{report.errors.size} 件、案 #{report.problems.size - report.errors.size} 件"
      report.problems.each { puts _1 }
    end
    exit 1 unless report.ok?
  end

  desc "Print the material an AI agent needs to write definitions: template fields, components, checks, JSON Schemas, examples (FORMAT=json for JSON). Made to be sent to an external LLM: no records, ids, bindings, codes or OPT files"
  task context: :environment do
    context = Definitions::Context.call
    next puts(JSON.pretty_generate(context)) if ENV["FORMAT"] == "json"

    puts "# 定義を書くための材料（rake definitions:context）"
    puts
    puts "定義を書いたら `bin/rails definitions:lint DIR=<組のディレクトリ>` で検査する。参照できるのは、下のテンプレートの項目だけ。"
    puts
    puts "## テンプレート"
    context[:templates].each do |template|
      puts
      puts "### #{template[:template_id]}"
      puts
      puts "| name | 見出し | 型 | 単位 | archetype_id | at-code |"
      puts "|---|---|---|---|---|---|"
      template[:fields].each do |field|
        puts "| #{field.values_at(:name, :label, :rm_type).join(' | ')} | #{field[:units]} | #{field[:archetype_id]} | #{field[:node_id]} |"
      end
    end
    puts
    puts "## 部品"
    puts
    context[:components].each { |component| puts "- `#{component[:name]}`: #{component[:shows]}。受け取るもの: #{component[:accepts]}" }
    puts
    puts context[:from_rule]
    puts
    puts "## 検査"
    puts
    context[:checks].each { |code, text| puts "- #{code}: #{text}" }
    puts
    puts "## スキーマ（JSON Schema。正は検査器）"
    context[:schemas].each do |kind, schema|
      puts
      puts "### #{kind}"
      puts
      puts "```json", JSON.pretty_generate(schema), "```"
    end
    puts
    puts "## 例"
    context[:examples].each do |path, text|
      puts
      puts "### #{path}"
      puts
      puts "```yaml", text.chomp, "```"
    end
  end

  desc "Print the transition diagram of a definition bundle as Mermaid text (DIR=path). Lints first; exits 1 without a diagram when there are errors"
  task diagram: :environment do
    dir = ENV["DIR"].to_s
    abort "使い方: bin/rails definitions:diagram DIR=<定義の組のディレクトリ>" if dir.empty?

    report = Definitions::Linter.call(dir)
    unless report.ok?
      puts "定義の組 #{dir}: エラー #{report.errors.size} 件。図は出さない"
      report.errors.each { puts _1 }
      exit 1
    end
    print Definitions::Diagram.from(report).to_mermaid
  end

  # 登録の入口（docs/design/definition-registration-plan.md 4 節、skoba/anlage#279、R-20261128-7 の回答 5）。
  # 認証が無いあいだ、書き込みは rake だけ。registered_by は運用者の名前（患者の記録や計測には使わない）
  operator = -> { "rake（#{Etc.getlogin || ENV['USER'] || 'unknown'}）" }
  find_bundle = lambda do
    bundle_id = ENV["BUNDLE"].to_s
    version = ENV["VERSION"].to_s
    abort "使い方: BUNDLE=<組の id> VERSION=<版>" if bundle_id.empty? || version.empty?
    DefinitionBundle.find_by(bundle_id:, version:) || (puts("組 #{bundle_id} の版 #{version} は無い") || exit(1))
  end

  desc "Register a definition bundle directory as a draft (DIR=path). Lints first; exits 1 when there are errors or the version is taken by other content"
  task register: :environment do
    dir = ENV["DIR"].to_s
    abort "使い方: bin/rails definitions:register DIR=<定義の組のディレクトリ>" if dir.empty?

    result = DefinitionBundle.register(Definitions::Files.read(dir), registered_by: operator.call)
    case result.status
    when :invalid
      puts "登録しなかった: エラー #{result.errors.size} 件"
      result.errors.each { puts _1 }
      exit 1
    when :exists then puts result.message
    when :conflict then puts(result.message) || exit(1)
    else
      bundle = result.bundle
      puts "組 #{bundle.bundle_id} の版 #{bundle.version} を下書きで登録した（id #{bundle.id}）。案 #{bundle.lint_report.size} 件"
    end
  end

  desc "Activate a registered version of a definition bundle (BUNDLE=id VERSION=x.y.z). The previous active version becomes superseded"
  task activate: :environment do
    bundle = find_bundle.call
    bundle.activate!
    puts "組 #{bundle.bundle_id} の版 #{bundle.version} を動かした"
  rescue DefinitionBundle::LintFailed => e
    puts "動かさなかった（いまのテンプレートで検査に通らない）:", e.message
    exit 1
  end

  desc "Restore an earlier version of a definition bundle (BUNDLE=id VERSION=x.y.z): copied as a new version and activated. History is kept"
  task restore: :environment do
    source = find_bundle.call
    restored = DefinitionBundle.restore!(source.bundle_id, source.version, registered_by: operator.call)
    puts "組 #{source.bundle_id} の版 #{source.version} の中身を、版 #{restored.version} として足して動かした"
  rescue DefinitionBundle::LintFailed => e
    puts "戻さなかった（いまのテンプレートで検査に通らない）:", e.message
    exit 1
  end

  desc "List registered definition bundles, their versions and states"
  task list: :environment do
    DefinitionBundle.order(:bundle_id, :id).group_by(&:bundle_id).each do |bundle_id, bundles|
      puts "組 #{bundle_id}"
      bundles.each do |bundle|
        puts "  #{bundle.version}  #{bundle.status}#{"（#{bundle.restored_from} から戻した）" if bundle.restored_from}"
      end
    end
  end
end
