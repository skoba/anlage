require "rails_helper"

# LLM を呼んだ回数と、トークンの数（docs/design/s4-nl-aql-plan.md 10.3 節）。日ごとに、ファイルに数える。表は足さない。
RSpec.describe Llm::Usage do
  let(:dir) { Pathname(Dir.mktmpdir) }
  let(:path) { dir.join("llm_usage.json") }
  let(:today) { Date.new(2026, 11, 27) }

  after { FileUtils.remove_entry(dir) }

  def usage(date = today)
    described_class.new(path: path, clock: -> { date })
  end

  it "ファイルが無いとき、きょうの回数は 0" do
    expect(usage.today).to eq(calls: 0, input_tokens: 0, output_tokens: 0)
    expect(path).not_to exist
  end

  it "呼んだ回数と、トークンの数を足す" do
    usage.record(Llm::Response.new(text: "{}", model: "m", input_tokens: 3000, output_tokens: 200))
    usage.record(Llm::Response.new(text: "{}", model: "m", input_tokens: 2900, output_tokens: 150))

    expect(usage.today).to eq(calls: 2, input_tokens: 5900, output_tokens: 350)
  end

  it "失敗した呼び出し（応答が無い）も 1 回に数える。トークンの数は足さない" do
    usage.record(nil)

    expect(usage.today).to eq(calls: 1, input_tokens: 0, output_tokens: 0)
  end

  it "トークンの数を返さないアダプタでも、回数は数える" do
    usage.record(Llm::Response.new(text: "{}", model: "m", input_tokens: nil, output_tokens: nil))

    expect(usage.today).to eq(calls: 1, input_tokens: 0, output_tokens: 0)
  end

  it "日が変わると、0 から数える。前の日の数は残る" do
    usage.record(nil)

    tomorrow = usage(today + 1)
    expect(tomorrow.today[:calls]).to eq(0)
    tomorrow.record(nil)
    expect(JSON.parse(path.read).keys).to eq(%w[2026-11-27 2026-11-28])
  end

  it "上限に達したかどうかを答える（0 は、1 回も呼べない）" do
    expect(usage.exhausted?(0)).to be(true)
    expect(usage.exhausted?(2)).to be(false)
    2.times { usage.record(nil) }
    expect(usage.exhausted?(2)).to be(true)
    expect(usage.exhausted?(3)).to be(false)
  end

  it "ファイルが壊れていたら、数えられないものとして、上限に達した扱いにする（呼びすぎの側に倒さない）" do
    path.write("{ 壊れている")

    expect(usage.exhausted?(100)).to be(true)
    expect(usage.today).to eq(calls: 0, input_tokens: 0, output_tokens: 0)
  end

  it "ファイルに書くのは、日付と数だけ" do
    usage.record(Llm::Response.new(text: "問いの文と応答", model: "m", input_tokens: 1, output_tokens: 2))

    expect(JSON.parse(path.read)).to eq("2026-11-27" => { "calls" => 1, "input_tokens" => 1, "output_tokens" => 2 })
  end
end
