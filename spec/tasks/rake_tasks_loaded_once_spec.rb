require "rails_helper"

# rake のタスクは、テストの全体で 1 回だけ読み込む（spec/support/rake_tasks.rb）。
# `Rails.application.load_tasks` を呼ぶたびに、同じタスクに同じ処理（action）が足され、invoke 1 回で処理が何度も走る。
# spec のファイルごとに読み込んでいたとき、全 suite では demo:reset が 1 回の invoke で 8 回走っていた
# （skoba/anlage#144。サンプルを 65 件にして、CI の test が 4 分から 16 分になったことで見つかった。docs/reports/sample-data-log.md R4）。
# 見るのは anlage のタスク（lib/tasks/*.rake の namespace）。Rails 自身の db:load_config と tmp は、1 回の読み込みでも処理が 2 つある
RSpec.describe "rake のタスクの読み込み" do
  it "anlage のタスクは、どれも処理（action）が 1 つまで" do
    namespaces = Rails.root.glob("lib/tasks/*.rake").map { "#{_1.basename('.rake')}:" }
    app_tasks = Rake::Task.tasks.select { |task| task.name.start_with?(*namespaces) }

    expect(app_tasks.map(&:name)).to include("demo:reset")
    expect(app_tasks.select { _1.actions.size > 1 }.map(&:name)).to eq([])
  end
end
