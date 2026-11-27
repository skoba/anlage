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
end
