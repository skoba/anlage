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
end
