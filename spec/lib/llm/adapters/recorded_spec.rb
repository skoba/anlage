require "rails_helper"

# 記録した応答を返すアダプタ（docs/design/s4-nl-aql-plan.md 3.1 節・7 節）。spec と CI と、測定の再現に使う。外を呼ばない。
# 記録は、送った文（指示文と入力）の sha256 を名前にした JSON のファイル。文が変わると、記録に当たらなくなる
RSpec.describe Llm::Adapters::Recorded do
  let(:dir) { Pathname(Dir.mktmpdir) }
  let(:adapter) { described_class.new(dir: dir) }

  after { FileUtils.remove_entry(dir) }

  def record(instructions:, input:, **fields)
    sha256 = Llm.fingerprint(instructions: instructions, input: input)
    dir.join("#{sha256}.json").write(JSON.generate({ sha256: sha256, input: input }.merge(fields)))
  end

  it "記録のファイルから、送った文の sha256 が同じ応答を返す" do
    record(instructions: "指示", input: "問い: 収縮期", response: %({"columns": [1]}), model: "recorded-by-hand",
           input_tokens: 12, output_tokens: 5)

    response = adapter.complete(instructions: "指示", input: "問い: 収縮期")

    expect(response.text).to eq(%({"columns": [1]}))
    expect(response.model).to eq("recorded-by-hand")
    expect(response.input_tokens).to eq(12)
    expect(response.output_tokens).to eq(5)
  end

  it "記録に無い文には、「記録が無い」で落ちる（黙って外を呼ばない）" do
    record(instructions: "指示", input: "問い: 収縮期", response: "{}")

    expect { adapter.complete(instructions: "指示", input: "問い: 拡張期") }
      .to raise_error(Llm::Error, /記録が無い/)
    expect { adapter.complete(instructions: "指示を変えた", input: "問い: 収縮期") }
      .to raise_error(Llm::Error, /記録が無い/)
  end

  it "壊れた記録は、Llm::Error で落ちる" do
    sha256 = Llm.fingerprint(instructions: "指示", input: "問い")
    dir.join("#{sha256}.json").write("{ 壊れている")

    expect { adapter.complete(instructions: "指示", input: "問い") }.to raise_error(Llm::Error, /記録が読めない/)
  end

  it "名前は recorded。外に文を送らない" do
    expect(adapter.name).to eq("recorded")
    expect(adapter).not_to be_external
  end
end
