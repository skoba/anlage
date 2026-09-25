require "rails_helper"

# skoba/anlage#38: LabResultReport（埋め込み CLUSTER 一段）を保存し、AQL で数値比較できる。
RSpec.describe "LabResultReport の保存と AQL 数値比較（#38）", type: :request do
  let!(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/LabResultReport.opt").read).tap(&:save!) }

  it "検査名・分析名・数値＋単位を保存し、CLUSTER 配下の magnitude で WHERE できる" do
    [ [ "空腹時血糖", "98" ], [ "HbA1c", "6.8" ] ].each do |analyte, value|
      post template_compositions_path(template.template_id), params: { values: {
        "laboratory_test_result_at0005" => "血液検査", "laboratory_test_analyte_at0024" => analyte,
        "laboratory_test_analyte_at0001" => value, "laboratory_test_analyte_at0001__units" => "mg/dL"
      } }
      expect(response).to have_http_status(:found)
    end

    query = <<~AQL
      SELECT cl/items[at0024]/value/value AS analyte, cl/items[at0001]/value/magnitude AS result
      FROM EHR e CONTAINS COMPOSITION c
           CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.laboratory_test_result.v1]
           CONTAINS CLUSTER cl[openEHR-EHR-CLUSTER.laboratory_test_analyte.v1]
      WHERE cl/items[at0001]/value/magnitude > 50
    AQL

    result = OpenehrRails::Aql::Executor.execute(query)

    expect(result.rows).to eq([ [ "空腹時血糖", 98.0 ] ])
  end
end
