require "rails_helper"

# 記録日時を指定して保存する（skoba/anlage#144、サンプルデータの記録日をずらす。docs/design/sample-data-plan.md 2 節の 3）。
# 指定が無ければ保存した時刻（docs/design/rm-attributes-without-inputs.md 2 節の規則 4）。
# 指定した時刻は、OBSERVATION の HISTORY.origin と EVENT.time、COMPOSITION の context/start_time に入る。
RSpec.describe Opt::RmCompositionCommitter, "recorded_at:" do
  let(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/CardiologyEncounter.opt").read).tap(&:save!) }
  let(:values) { { "blood_pressure_at0004" => "148", "blood_pressure_at0005" => "86" } }
  let(:recorded_at) { Time.zone.parse("2026-01-15T00:00:00Z") }

  def observation(result)
    result.composition.to_rm.content.first
  end

  it "指定した時刻が、イベントの時刻・履歴の起点・context の start_time に入る" do
    result = described_class.call(template, values, recorded_at: recorded_at)

    expect(observation(result).data.events.first.time.value).to eq("2026-01-15T00:00:00Z")
    expect(observation(result).data.origin.value).to eq("2026-01-15T00:00:00Z")
    expect(result.composition.context_start_time).to eq(recorded_at)
  end

  it "指定が無ければ保存した時刻" do
    travel_to(Time.zone.parse("2026-11-25T03:00:00Z")) do
      result = described_class.call(template, values)

      expect(observation(result).data.events.first.time.value).to eq("2026-11-25T03:00:00Z")
      expect(result.composition.context_start_time).to eq(Time.zone.parse("2026-11-25T03:00:00Z"))
    end
  end

  include ActiveSupport::Testing::TimeHelpers
end
