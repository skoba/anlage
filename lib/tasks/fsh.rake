require "open3"
require "yaml"

# fsh-plan v1 の出力提供形（`docs/design/fsh-plan.md` 判断4: `rake fsh:export`）と
# Sushi 検証（同 判断3: ローカル・手動実行の rake タスクまで。CI には組み込まない）。
# FSH 本文は gem の `OpenehrRails::Fhir::FshGenerator` の出力そのもので、Anlage 側
# では再導出しない（同 plan Step 2「源の確定」）。Anlage が足すのは、テンプレート
# ごとに sushi がそのまま読める最小の SUSHI プロジェクト骨格だけ。
namespace :fsh do
  default_output_dir = -> { Rails.root.join("tmp/fsh") }
  project_name_for = ->(template) { "#{template.template_id}-#{template.version}".parameterize }

  # sushi が FSHOnly で要求する最小構成（id/name/title は IG 生成専用で、置くと
  # sushi が「未使用」と警告する）。canonical は Anlage の公開 URL ではなく
  # 検証用のプレースホルダ（生成 Profile の url 前置きにしか使われない）。
  sushi_config_for = lambda do |template, project_name|
    {
      "canonical" => "http://example.org/anlage/#{project_name}",
      "status" => "draft",
      "version" => template.version,
      "fhirVersion" => "5.0.0",
      "FSHOnly" => true
    }.to_yaml
  end

  desc "Export FSH for every active template, one SUSHI project each (default: tmp/fsh)"
  task :export, [ :output_dir ] => :environment do |_task, args|
    output_root = Pathname(args[:output_dir] || default_output_dir.call)

    Template.active.find_each do |template|
      opt = Opt::SafeParser.parse(template.source_xml)
      fsh_files = OpenehrRails::Fhir::FshGenerator.new(opt).to_fsh_files
      project_name = project_name_for.call(template)
      project_dir = output_root.join(project_name)
      fsh_dir = project_dir.join("input/fsh")
      fsh_dir.mkpath
      project_dir.join("sushi-config.yaml").write(sushi_config_for.call(template, project_name))
      fsh_files.each { |profile_id, fsh| fsh_dir.join("#{profile_id}.fsh").write(fsh) }
      puts "#{project_name}: #{fsh_files.size} profile(s) -> #{project_dir}"
    end
  end

  desc "Compile every exported SUSHI project with sushi and report Errors/Warnings (sushi must be on PATH)"
  task :verify, [ :output_dir ] => :environment do |_task, args|
    output_root = Pathname(args[:output_dir] || default_output_dir.call)

    begin
      version, _status = Open3.capture2e("sushi", "--version")
    rescue Errno::ENOENT
      abort "sushi not found on PATH (install with `npm install -g fsh-sushi@3.16.0`; " \
            "the version is pinned in openehr-ruby docs/backlog.md)"
    end
    puts version.strip

    project_dirs = output_root.children.select { |dir| dir.join("sushi-config.yaml").exist? }.sort
    results = project_dirs.map do |project_dir|
      output, _status = Open3.capture2e("sushi", project_dir.to_s)
      errors = output[/(\d+)\s+Errors?/, 1].to_i
      warnings = output[/(\d+)\s+Warnings?/, 1].to_i
      puts "#{project_dir.basename}: #{errors} Errors, #{warnings} Warnings"
      errors
    end
    puts "Total: #{results.sum} Errors across #{results.size} project(s)"
  end
end
