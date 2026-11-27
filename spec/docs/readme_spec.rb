require "rails_helper"

# README と、追跡している文書が、空になっていないこと（regression pin。裁定 R-20261127-27）。
# 2026-11-27 に、README.ja.md が 0 バイトのまま main に入った（PR #240。1 行を直すつもりのスクリプトが、
# 読む前にファイルを書き込み用に開いて、中身を消した。差分の 185 行の削除を見ずにマージした）。
RSpec.describe "README と文書" do
  let(:english) { Rails.root.join("README.md").read }
  let(:japanese) { Rails.root.join("README.ja.md").read }

  it "README.md と README.ja.md は、空でない（見出しと本文がある）" do
    [ english, japanese ].each do |text|
      expect(text.lines.size).to be > 50
      expect(text).to match(/^# /)
    end
  end

  it "README.md と README.ja.md は、先頭で互いに案内している" do
    expect(english.lines.first(10).join).to include("[日本語](README.ja.md)")
    expect(japanese.lines.first(10).join).to include("[English](README.md)")
  end

  it "追跡している .md に、0 バイトのものが無い" do
    tracked = `git -C #{Rails.root} ls-files -z -- '*.md'`.split("\0")

    expect(tracked).to include("README.md", "README.ja.md")
    expect(tracked.select { |path| Rails.root.join(path).file? && Rails.root.join(path).zero? }).to be_empty
  end
end
