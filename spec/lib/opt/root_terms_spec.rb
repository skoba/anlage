require "rails_helper"

# openehr 2.5.0（skoba/openehr-ruby#58）で CArchetypeRoot がルートごとの term_definitions を持つようになった。
# Opt::RootTerms は、パース済みの OPT からそれを「ルートの RM path → 出現順の配列」に並べる。
# それまでの迂回（Opt::TemplateTerms、OPT の XML を Nokogiri で再解析）を置き換える。
RSpec.describe Opt::RootTerms do
  def terms_of(fixture)
    described_class.call(Opt::SafeParser.parse(Rails.root.join("spec/fixtures/opt/#{fixture}").read))
  end

  it "ルートの path ごとに、そのルートの at-code → text・description を返す（ProblemList）" do
    terms = terms_of("ProblemList.opt")

    expect(terms.keys).to contain_exactly("", "/content[openEHR-EHR-EVALUATION.problem_diagnosis.v1]")
    diagnosis = terms["/content[openEHR-EHR-EVALUATION.problem_diagnosis.v1]"]
    expect(diagnosis.size).to eq(1)
    expect(diagnosis.first.fetch("at0002").keys).to contain_exactly("text", "description")
  end

  it "同じ path に同じアーキタイプが 2 回埋め込まれていれば、文書順に 2 つ返し、改名された名前を別々に持つ（jp_referral の clinical_synopsis）" do
    synopsis = terms_of("jp_referral.opt")["/content[openEHR-EHR-SECTION.referral_details.v0]/items[openEHR-EHR-EVALUATION.clinical_synopsis.v1]"]

    expect(synopsis.size).to eq(2)
    expect(synopsis.map { |terms| terms.dig("at0000", "text") }.uniq.size).to eq(2)
  end

  it "SECTION のルートの名前を持つ（jp_referral）" do
    expect(terms_of("jp_referral.opt").dig("/content[openEHR-EHR-SECTION.referral_details.v0]", 0, "at0000", "text"))
      .to eq("紹介状の詳細情報")
  end
end

RSpec.describe "OPT の XML を自前で再解析しない（Opt::TemplateTerms の撤去）" do
  let(:source_xml) { Rails.root.join("spec/fixtures/opt/jp_referral.opt").read }

  it "登録（web_template の組み立て）とパスカードの抽出は、XML を読み直さない（Opt::SafeParser.safe_document を呼ばない）" do
    expect(Opt::SafeParser).not_to receive(:safe_document)

    template = Template.build_from_opt_xml(source_xml)
    Opt::PathcardExtractor.call(template)
  end
end
