require "rake"

# rake のタスクは、テストの全体で 1 回だけ読み込む（skoba/anlage#144、spec/tasks/rake_tasks_loaded_once_spec.rb）。
# `Rails.application.load_tasks` は呼ぶたびに同じタスクへ処理を足すので、spec のファイルごとには呼ばない。
# Evaluation::Datasets.build も、読み込み済みなら読み込まない（app/lib/evaluation/datasets.rb）。
Rails.application.load_tasks if Rake::Task.tasks.empty?
