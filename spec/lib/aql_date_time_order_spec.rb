require "rails_helper"

# 既知の制限 20（R-20261127-20 の 1）の regression pin。openehr 2.6.1 では、DV_DATE_TIME の magnitude が
# 1 年を 365.24 日・1 か月を 30.42 日として数えるため、月末の昼すぎと翌月 1 日の早い時刻で順序が逆になった
# （openehr-ruby#117。2.9.0 で直った）。記録は ProblemList.opt（CKM 由来の実物）を committer で入れる。
RSpec.describe "AQL の日時の順序（既知の制限 20）" do
  let(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!) }
  let(:month_end) { Time.utc(2026, 1, 31, 12, 0, 0) }
  let(:next_month) { Time.utc(2026, 2, 1, 0, 0, 0) }

  before do
    Opt::RmCompositionCommitter.call(template, { "problem_diagnosis_at0002" => "月末" }, recorded_at: month_end)
    Opt::RmCompositionCommitter.call(template, { "problem_diagnosis_at0002" => "翌月" }, recorded_at: next_month)
  end

  def names(aql)
    OpenehrRails::Aql::Executor.execute(aql).rows.map(&:first)
  end

  it "日時そのものの ORDER BY で、月末の昼すぎが翌月 1 日の 0 時より先に来る" do
    expect(names(<<~AQL)).to eq(%w[月末 翌月])
      SELECT ev/data[at0001]/items[at0002]/value/value
      FROM EHR e CONTAINS COMPOSITION c CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
      ORDER BY c/context/start_time ASC
    AQL
  end

  it "magnitude の ORDER BY でも、同じ順になる" do
    expect(names(<<~AQL)).to eq(%w[月末 翌月])
      SELECT ev/data[at0001]/items[at0002]/value/value
      FROM EHR e CONTAINS COMPOSITION c CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
      ORDER BY c/context/start_time/magnitude ASC
    AQL
  end

  it "DvDateTime の比較で、月末の昼すぎが翌月 1 日の 0 時より前" do
    dv = ->(value) { OpenEHR::RM::DataTypes::Quantity::DateTime::DvDateTime.new(value: value) }

    expect(dv.("2026-01-31T12:00:00Z")).to be < dv.("2026-02-01T00:00:00Z")
  end
end
