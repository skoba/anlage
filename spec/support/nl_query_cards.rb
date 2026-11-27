# 自然言語から AQL（S4）の spec が使うカード。実物の OPT（spec/fixtures/opt/*.opt）から抽出する。捏造しない
RSpec.shared_context "nl_query のカード" do
  before do
    %w[CardiologyEncounter ProblemList LabResultReport].each do |fixture_name|
      template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture_name}.opt").read)
      template.pathcards = Opt::PathcardExtractor.call(template).cards
      template.save!
    end
  end

  let(:corpus) { QueryBuilder::Corpus.active }

  def card(template_id, archetype_id, at_code)
    corpus.cards.find do |candidate|
      candidate["identity"].values_at("template_id", "archetype_id", "at_code") == [ template_id, archetype_id, at_code ]
    end || raise("カードが無い: #{template_id} #{archetype_id} #{at_code}")
  end

  let(:systolic) { card("CardiologyEncounter", "openEHR-EHR-OBSERVATION.blood_pressure.v2", "at0004") }
  let(:diastolic) { card("CardiologyEncounter", "openEHR-EHR-OBSERVATION.blood_pressure.v2", "at0005") }
  let(:diagnosis) { card("ProblemList", "openEHR-EHR-EVALUATION.problem_diagnosis.v1", "at0002") }
  let(:certainty) { card("ProblemList", "openEHR-EHR-EVALUATION.problem_diagnosis.v1", "at0073") }
  let(:onset) { card("ProblemList", "openEHR-EHR-EVALUATION.problem_diagnosis.v1", "at0077") }
  let(:analyte_name) { card("LabResultReport", "openEHR-EHR-CLUSTER.laboratory_test_analyte.v1", "at0024") }
  # 候補の並び（番号は 1 から）: 1 収縮期、2 拡張期、3 プロブレム・診断名、4 診断確度、5 発症日時、6 分析名
  let(:candidates) { [ systolic, diastolic, diagnosis, certainty, onset, analyte_name ] }
end
