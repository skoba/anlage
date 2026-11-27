require "rails_helper"

# AQL を書かせる 3 つの腕（N0・N1・G-AQL）に送る文（計画書 5.1 節・12.2 節。R-20261127-32）。
# 方言の説明（指示文）は、3 つの腕で同じ。違うのは、入力に何を足すかだけ（N0: 問いだけ、N1: アーキタイプの ID、G-AQL: カードの文）
RSpec.describe Evaluation::Grounding::AqlPrompt do
  before { Evaluation::Datasets.build("demo_initial") }

  let(:corpus) { QueryBuilder::Corpus.active }
  let(:question) { "診断確度が「疑い」の傷病の、傷病名" }

  def prompt(arm) = described_class.new(arm: arm, question: question, corpus: corpus)

  it "方言の説明（指示文）は、3 つの腕で同じ文" do
    expect(prompt(:n1).instructions).to eq(prompt(:n0).instructions)
    expect(prompt(:g_aql).instructions).to eq(prompt(:n0).instructions)
  end

  it "方言の説明に、出力の決まりがある: 出所は最初の列、ほかは問いの文の順。AQL は複数返してよい" do
    text = prompt(:n0).instructions

    expect(text).to include("記録の出所（template_id）を出すときは、最初の列に置く。ほかの列は、問いの文に出てくる順")
    expect(text).to include("c/archetype_details/template_id/value")
    expect(text).to include('{"aqls": [')
    expect(text).to include("日時の項目では ORDER BY を使わない")
  end

  it "N0 の入力は、問いだけ。アーキタイプの ID も、カードの文も入らない" do
    input = prompt(:n0).input

    expect(input).to include("問い: #{question}")
    expect(input).not_to include("openEHR-EHR")
    expect(input).not_to include("診断確度 |")
  end

  it "N1 の入力は、問いと、索引にあるアーキタイプの ID の一覧。パスとラベルは入らない" do
    input = prompt(:n1).input

    expect(input).to include("openEHR-EHR-EVALUATION.problem_diagnosis.v1")
    expect(input).to include("openEHR-EHR-OBSERVATION.blood_pressure.v1")
    expect(input).not_to include("at0073")
    expect(input).not_to include("プロブレム・診断名")
  end

  it "G-AQL の入力は、問いと、カードの文（ラベル、型、値集合のコード、FROM の形、SELECT に書くパス）" do
    input = prompt(:g_aql).input

    expect(input).to include("診断確度")
    expect(input).to include("疑い=at0074")
    expect(input).to include("EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]")
    expect(input).to include("ev/data[at0001]/items[at0073]/value")
  end

  it "どの腕にも、説明、bindings のコードは入らない" do
    %i[n0 n1 g_aql].each do |arm|
      text = prompt(arm).instructions + prompt(arm).input
      expect(text).not_to include("SNOMED")
      expect(text).not_to include("The level of confidence")
    end
  end

  it "送る文の sha256 は、腕ごとに違い、同じ入力なら同じ" do
    expect(prompt(:n0).sha256).not_to eq(prompt(:n1).sha256)
    expect(prompt(:g_aql).sha256).to eq(prompt(:g_aql).sha256)
  end
end
