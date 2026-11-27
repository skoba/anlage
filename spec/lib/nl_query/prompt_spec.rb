require "rails_helper"
require "support/nl_query_cards"

# LLM に渡す文を組む（docs/design/s4-nl-aql-plan.md 4.2・4.3）。送ってよい項目だけを並べる作りで、
# パス・at-code・説明・bindings・provenance は文に入らない（コンテンツ防火壁、LLM 分業原理）。
RSpec.describe NlQuery::Prompt do
  include_context "nl_query のカード"

  let(:prompt) { described_class.new(question: "診断確度が「疑い」の傷病名", cards: candidates) }

  describe "#card_lines（候補のカードを、番号つきの 1 行ずつにする）" do
    it "番号、ラベル、容器の名前、型、値集合の表示名、単位、テンプレートを、この順に並べる" do
      expect(prompt.card_lines).to eq([
        "1 | 収縮期 | 血圧 | 数値 |  | mm[Hg] | CardiologyEncounter",
        "2 | 拡張期 | 血圧 | 数値 |  | mm[Hg] | CardiologyEncounter",
        "3 | プロブレム・診断名 | プロブレム・診断 | 文字列 |  |  | ProblemList",
        "4 | 診断確度 | プロブレム・診断 | 値集合 | 疑い、推定、確定 |  | ProblemList",
        "5 | 発症日時 | プロブレム・診断 | 日時 |  |  | ProblemList",
        "6 | 分析名 | 検体検査結果／検査分析結果 | 文字列 |  |  | LabResultReport"
      ])
    end
  end

  describe "#input（アダプタに渡す入力）" do
    it "候補のカードの行と、問いが入る" do
      expect(prompt.input).to include("4 | 診断確度 | プロブレム・診断 | 値集合 | 疑い、推定、確定 |  | ProblemList")
      expect(prompt.input).to include("問い: 診断確度が「疑い」の傷病名")
    end

    it "パス、アーキタイプの ID、at-code は現れない" do
      text = prompt.instructions + prompt.input
      candidates.each do |card|
        expect(text).not_to include(card.dig("identity", "path"))
        expect(text).not_to include(card.dig("identity", "archetype_id"))
      end
      expect(text).not_to match(/at\d{4}/)
    end

    it "説明（英語の原文が多い）は現れない" do
      descriptions = candidates.flat_map { |card| Array(card.dig("semantics", "descriptions")).map { |entry| entry["text"] } }.compact
      expect(descriptions).not_to be_empty
      descriptions.each { |description| expect(prompt.input).not_to include(description) }
    end

    it "bindings に SNOMED CT のコードを持つカードを渡しても、コードが現れない" do
      code = systolic.fetch("bindings").first.fetch("code")
      expect(code).to include("SNOMED-CT")
      expect(prompt.input).not_to include("SNOMED")
      expect(prompt.input).not_to include(code[/\d{6,}/])
    end

    # いまの fixture の OPT には、code_list に at-code でないコードを持つものが無い（実測。docs/reports/s4-nl-query-log.md R1）。
    # 実物の「診断確度」のカードの値集合に、実物の収縮期のカードの binding のコードを 1 行足した形で確かめる
    it "値集合の表示名は、コードが at-code のものだけが入る（外の用語のコードの表示名は現れない）" do
      external = systolic.fetch("bindings").first.fetch("code")
      derived = certainty.deep_dup
      derived["constraints"]["value"]["code_list"] << { "code" => external, "label" => "外の用語の表示名" }

      line = described_class.new(question: "x", cards: [ derived ]).card_lines.first
      expect(line).to include("疑い、推定、確定")
      expect(line).not_to include("外の用語の表示名")
    end

    it "カードの文言に区切りの文字や改行があっても、1 枚が 1 行のまま" do
      odd = diagnosis.deep_dup
      odd["semantics"]["labels"][0]["text"] = "診断 | 名\n2 行目"

      lines = described_class.new(question: "x", cards: [ odd ]).card_lines
      expect(lines.size).to eq(1)
      expect(lines.first.count("|")).to eq(6)
    end
  end

  describe "#sha256" do
    it "同じ入力から、いつも同じ文ができる" do
      again = described_class.new(question: "診断確度が「疑い」の傷病名", cards: candidates)
      expect(again.input).to eq(prompt.input)
      expect(again.sha256).to eq(prompt.sha256)
      expect(prompt.sha256).to match(/\A\h{64}\z/)
    end

    it "問いが変われば、変わる" do
      other = described_class.new(question: "収縮期血圧が 140 以上", cards: candidates)
      expect(other.sha256).not_to eq(prompt.sha256)
    end
  end

  describe "#instructions（決まった指示文）" do
    it "問いやカードによらず同じ" do
      other = described_class.new(question: "収縮期血圧が 140 以上", cards: [ systolic ])
      expect(other.instructions).to eq(prompt.instructions)
    end

    it "使える演算子は、クエリビルダーが持つものと同じ" do
      QueryBuilder::Builder::OPERATORS.values.flatten.uniq.each do |operator|
        expect(prompt.instructions).to include(operator)
      end
    end
  end
end
