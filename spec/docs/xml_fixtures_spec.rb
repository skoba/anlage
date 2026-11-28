require "rails_helper"

# 追跡している XML の fixture（OPT を含む）が、整形式であること（R-20261128-13、skoba/anlage#284）。
# いまの読み取り（Nokogiri の既定、RECOVER）では読めても、厳しく読むパーサは整形式でないファイルを断る。
# 2026-11-28 に、bmi_calculation.opt の先頭の出どころの注釈に `--` があった（XML 1.0 の 2.5 節は、注釈の中の `--` を認めない）
RSpec.describe "XML の fixture" do
  tracked = IO.popen([ "git", "-C", Rails.root.to_s, "ls-files", "-z", "--", "*.opt", "*.xml" ], &:read).split("\0")

  it "追跡している *.opt と *.xml がある" do
    expect(tracked).to include("spec/fixtures/opt/bmi_calculation.opt")
  end

  it "どれも、STRICT で読める（整形式）" do
    broken = tracked.filter_map do |path|
      Nokogiri::XML(Rails.root.join(path).read, &:strict)
      nil
    rescue Nokogiri::XML::SyntaxError => e
      "#{path}: #{e.message.lines.first.strip}"
    end

    expect(broken).to be_empty, "整形式でない XML:\n#{broken.join("\n")}"
  end
end
