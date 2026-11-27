require "rails_helper"

# 定義の YAML は安全な読み方だけで読む（docs/design/definition-layer-plan.md 9 節、skoba/anlage#257）。
# 別名（alias）と任意のクラスを許さない。1 ファイルの大きさに上限を置く。読めないものは例外にせず、D1 の問題として返す
RSpec.describe Definitions::Loader do
  def load(text, path: "screens/x.yml") = described_class.parse(text, path:)

  it "ふつうの YAML は Hash として読む" do
    result = load("screen: x\nversion: 1.0.0\n")

    expect(result.data).to eq("screen" => "x", "version" => "1.0.0")
    expect(result.problems).to be_empty
  end

  it "別名（alias）は読まない（D1）" do
    result = load("a: &x { k: 1 }\nb: *x\n")

    expect(result.data).to be_nil
    expect(result.problems.map(&:code)).to eq([ "D1" ])
    expect(result.problems.first.message).to include("別名")
  end

  it "任意のクラス（!ruby/object）は読まない（D1）" do
    result = load("--- !ruby/object:OpenStruct\nfoo: 1\n")

    expect(result.data).to be_nil
    expect(result.problems.first.message).to include("使えない型")
  end

  it "日付も文字列のまま読まない型（Date）は D1" do
    expect(load("version: 2026-11-27\n").problems.map(&:code)).to eq([ "D1" ])
  end

  it "上限（64 KiB）を超えるファイルは読まない（D1）" do
    result = load("title: #{'a' * (64 * 1024)}\n")

    expect(result.data).to be_nil
    expect(result.problems.first.message).to include("64 KiB")
  end

  it "文法の誤りは D1。行を文に入れる" do
    result = load("screen: [\n")

    expect(result.problems.map(&:code)).to eq([ "D1" ])
    expect(result.problems.first.definition).to eq("screens/x.yml")
  end

  it "最上位が Hash でなければ D1" do
    expect(load("- a\n- b\n").problems.first.message).to include("最上位")
  end
end
