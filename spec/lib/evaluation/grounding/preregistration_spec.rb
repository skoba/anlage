require "rails_helper"

# 測る前に決めておいたこと（docs/reports/s4-runs/preregistration.yml。計画書 5.6 節。R-20261127-32）と、いまのコードが食い違わないこと。
# 指示文や問いのファイルを変えると、ここが落ちる。変えるときは、理由と、変える前の結果を、preregistration.md に残してから、値を直す。
RSpec.describe "測定の、先に決めておいたこと" do
  let(:registered) { YAML.load_file(Rails.root.join("docs/reports/s4-runs/preregistration.yml"), permitted_classes: [ Date ]) }

  it "問いのファイル、方言の説明、選択の指示文、選択の形の sha256 が、決めたときのまま" do
    expect(Evaluation::Grounding::Queries.sha256).to eq(registered.fetch("queries_sha256"))
    expect(Digest::SHA256.hexdigest(Evaluation::Grounding::AqlPrompt::DIALECT)).to eq(registered.fetch("dialect_sha256"))
    expect(Digest::SHA256.hexdigest(NlQuery::Prompt::INSTRUCTIONS)).to eq(registered.fetch("selection_instructions_sha256"))
    expect(Digest::SHA256.hexdigest(JSON.generate(NlQuery::Prompt::JSON_SCHEMA))).to eq(registered.fetch("selection_json_schema_sha256"))
  end

  it "腕、くり返しの回数、指標が、決めたときのまま" do
    expect(registered.fetch("arms")).to eq(Evaluation::Grounding::Run::ARMS.map(&:to_s))
    expect(registered.fetch("repeats")).to eq(5)
    expect(registered.fetch("primary_metric")).to eq("match")
    expect(registered.fetch("secondary_metric")).to eq("order_free")
    expect(Evaluation::Grounding::Queries.load.size).to eq(registered.fetch("queries"))
  end
end
