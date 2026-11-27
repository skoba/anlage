require "rails_helper"

# 患者の記録を部品に配る（skoba/anlage#219、U1-2）。データは demo_initial（rake demo:reset の初期状態。docs/design/sample-data-plan.md）
RSpec.describe Charts::PatientChart do
  before { Evaluation::Datasets.build("demo_initial") }

  def chart(subject_id) = described_class.call(OpenehrRails::Rm::Ehr.find_by!(subject_id: subject_id))

  it "DEMO-01 のプロブレムリストは 3 行。確度は値集合の表示（確定）、発症日は記録の値" do
    rows = chart("DEMO-01").problems

    expect(rows.map(&:diagnosis)).to contain_exactly("2型糖尿病", "糖尿病性腎症", "高血圧症")
    expect(rows.map(&:certainty)).to all(eq("確定"))
    expect(rows.find { _1.diagnosis == "高血圧症" }.onset).to start_with("2020-06-01")
  end

  it "DEMO-01 の収縮期（CardiologyEncounter）の系列は 4 点、日付の古い順、単位 mm[Hg]" do
    series = chart("DEMO-01").series.find { _1.template_id == "CardiologyEncounter" && _1.label == "収縮期" }

    expect(series.points.map(&:value)).to eq([ 148.0, 152.0, 138.0, 134.0 ])
    expect(series.points.map(&:at)).to eq(series.points.map(&:at).sort)
    expect(series.units).to eq("mm[Hg]")
  end

  it "DEMO-01 の検査結果の時系列表は、行が分析名（単位）、点は日付の古い順" do
    rows = chart("DEMO-01").lab_rows

    expect(rows.map { [ _1.name, _1.units ] }).to eq([ [ "空腹時血糖", "mg/dL" ], [ "HbA1c", "%" ], [ "クレアチニン", "mg/dL" ] ])
    expect(rows.find { _1.name == "HbA1c" }.points.map(&:value)).to eq([ 8.1, 7.6, 7.2 ])
  end

  it "DEMO-07 の検査は 5 行、各 1 点。紹介状のテンプレートが未登録なので、紹介状はそのほかの記録" do
    result = chart("DEMO-07")

    expect(result.lab_rows.map(&:name)).to eq([ "白血球数", "芽球（末梢血）", "ヘモグロビン", "血小板数", "LDH" ])
    expect(result.lab_rows.map { _1.points.size }).to all(eq(1))
    expect(result.orders).to be_empty
    expect(result.others.map(&:template_id)).to eq([ "jp_referral" ])
  end

  it "削除した記録は部品に入らない。修正した記録は最新の版の値" do
    ehr = OpenehrRails::Rm::Ehr.find_by!(subject_id: "DEMO-03")
    template = Template.active.find_by!(template_id: "CardiologyEncounter")
    records = OpenehrRails::Rm::Composition.latest.not_deleted.where(ehr:, template_id: "CardiologyEncounter").order(:context_start_time).to_a
    first, second = records.first(2)
    OpenehrRails::Rm::CompositionCommitter.delete(uid: first.uid, ehr:)
    values = Opt::CompositionReader.call(template, JSON.generate(second.to_canonical_hash)).merge("blood_pressure_at0004" => "99")
    Opt::RmCompositionCommitter.call(template, values, ehr:, uid: second.uid, recorded_at: Opt::RecordedTime.of(second.to_canonical_hash))

    points = described_class.call(ehr).series.find { _1.template_id == "CardiologyEncounter" && _1.label == "収縮期" }.points

    expect(points.size).to eq(records.size - 1)
    expect(points.first.value).to eq(99.0)
  end
end
