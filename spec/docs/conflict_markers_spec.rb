require "rails_helper"

# 追跡しているファイルに、マージの競合の印が残っていないこと（regression pin。裁定 R-20261128-1）。
# 2026-11-27 に、終わっていないマージをコミットして、docs/reports/definitions-log.md に
# `<<<<<<<`・`>>>>>>>` の行が残った（5ccf342。PR #262 の中で 7518ca4 で消した）。
RSpec.describe "競合の印" do
  # 行の頭の 7 文字と、そのあとの空白か行末。`=======` は Markdown の見出しの下線と区別できないので見ない
  it "追跡しているテキストのファイルに、行の頭の <<<<<<< と >>>>>>> が無い" do
    output = IO.popen([ "git", "-C", Rails.root.to_s, "grep", "-nIE", "^(<<<<<<<|>>>>>>>)( |$)" ], &:read)
    marker = /\A(<<<<<<<|>>>>>>>)( |\z)/
    found = output.lines.select { |line| line.split(":", 3).last.chomp.match?(marker) }

    expect(found).to be_empty, "競合の印が残っている:\n#{found.join}"
  end
end
