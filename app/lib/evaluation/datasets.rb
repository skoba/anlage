require "rake"

module Evaluation
  # aql の問いが前提にする名前つきデータセット（docs/design/s1-eval-v2-plan.md 2.3、判断 D3）。
  # demo_initial は rake demo:reset と同じ初期状態。手順を写さず、同じ rake タスクを呼ぶ
  # （spec/demo/cross_template_query_spec.rb と同じ作り方）。
  module Datasets
    class UnknownDataset < StandardError; end

    NAMES = %w[demo_initial].freeze

    module_function

    def build(name)
      raise UnknownDataset, "データセット #{name.inspect} は無い（#{NAMES.join('／')}）" unless NAMES.include?(name)

      Rails.application.load_tasks if Rake::Task.tasks.empty?
      Rake::Task["demo:reset"].reenable
      Rake::Task["demo:reset"].invoke
    end
  end
end
