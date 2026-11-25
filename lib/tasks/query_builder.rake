# クエリビルダー（docs/design/s2-cross-version-plan.md）
namespace :query_builder do
  desc "List candidate version mappings (same archetype ID without version, at-code, path and RM type) from active templates. Prints Markdown; does not edit config/version_mappings.yml"
  task version_candidates: :environment do
    candidates = QueryBuilder::VersionCandidates.call(QueryBuilder::Corpus.active)
    rows = QueryBuilder::VersionMappings.default.rows.index_by { |row| [ row.concept, row.at_code ] }

    puts "# アーキタイプの版の対応の候補（#{candidates.size} 件）"
    puts
    puts "候補は「同じものかもしれない」まで。問い合わせに使うのは、人間がレビューして active にした行だけ（config/version_mappings.yml）。"
    puts
    puts "| アーキタイプ（版を除く） | 項目 | 版 | ラベル | 型 | 違い（単位・値の範囲・値集合） | いまの表 |"
    puts "|---|---|---|---|---|---|---|"
    candidates.each do |candidate|
      labels = candidate.labels.map { |version, label| "#{version}: #{label}" }.join("／")
      status = rows[[ candidate.concept, candidate.at_code ]]&.status || "（行なし）"
      puts "| #{candidate.concept} | #{candidate.at_code} | #{candidate.versions.join('、')} | #{labels} | #{candidate.rm_type} | " \
           "#{candidate.differences.presence&.join('、') || 'なし'} | #{status} |"
    end
  end
end
