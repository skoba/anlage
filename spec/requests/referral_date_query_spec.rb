require "rails_helper"

# 紹介日（COMPOSITION の context/start_time）で引ける（skoba/anlage#146、R-20261124-20 作業列 3）。
# start_time は保存した時刻（docs/design/rm-attributes-without-inputs.md 2 節の規則 4、5 節の 5）。
# openehr 2.6.0 で AQL が context に届き、openehr-rails は CompositionCommitter の context_start_time: を
# context_start_time 列に持つ（0.10.0 lib/openehr_rails/rm/composition_committer.rb:12-41、rm_object_builder.rb:97-106）。
# setting は anlage では決めない（OPT に制約が無い。gem が組む）。
RSpec.describe "紹介日（context/start_time）で引ける", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  REFERRAL_DATE_AQL = <<~AQL.freeze
    SELECT c/context/start_time/value AS referred_at,
           ev/data[at0001]/items[at0002]/value/value AS diagnosis
    FROM EHR e CONTAINS COMPOSITION c
         CONTAINS EVALUATION ev[openEHR-EHR-EVALUATION.problem_diagnosis.v1]
    WHERE c/context/start_time/value >= "2026-04-01T00:00:00Z"
      AND c/context/start_time/value < "2026-05-01T00:00:00Z"
  AQL

  let!(:referral) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/jp_referral.opt").read).tap(&:save!) }

  def refer(diagnosis, at:)
    travel_to(Time.zone.parse(at)) do
      post "/compositions/#{referral.template_id}",
           params: { values: { "service_request_at0121" => "精査依頼", "problem_diagnosis_at0002" => diagnosis } }
    end
    expect(response).to have_http_status(:redirect)
  end

  it "フォームから保存した紹介状を、紹介日の期間で絞って、紹介日と傷病名を引ける" do
    refer("2型糖尿病", at: "2026-04-15T00:00:00Z")
    refer("高血圧症", at: "2026-06-01T00:00:00Z")

    rows = OpenehrRails::Aql::Executor.execute(REFERRAL_DATE_AQL).rows

    expect(rows).to eq([ [ "2026-04-15T00:00:00Z", "2型糖尿病" ] ])
  end

  it "修正しても紹介日は元の記録の日のまま（同じ uid の新しい版は context を引き継ぐ）" do
    problem_list = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!)
    travel_to(Time.zone.parse("2026-04-15T00:00:00Z")) do
      post "/compositions/#{problem_list.template_id}", params: { values: { "problem_diagnosis_at0002" => "高血圧症" } }
    end
    composition = Composition.order(:id).last
    travel_to(Time.zone.parse("2026-06-01T00:00:00Z")) do
      patch "/compositions/#{composition.id}", params: { values: { "problem_diagnosis_at0002" => "本態性高血圧症" } }
    end

    rows = OpenehrRails::Aql::Executor.execute(REFERRAL_DATE_AQL).rows

    expect(rows).to eq([ [ "2026-04-15T00:00:00Z", "本態性高血圧症" ] ])
  end

  # 削除の版（lifecycle 523）も同じ uid の新しい版。論理削除の記録は AQL に残る（上流候補 28 項）ので、紹介日も元のまま
  it "削除しても、削除の版の紹介日は元の記録の日のまま" do
    refer("2型糖尿病", at: "2026-04-15T00:00:00Z")
    composition = Composition.order(:id).last
    travel_to(Time.zone.parse("2026-06-01T00:00:00Z")) { delete "/compositions/#{composition.id}" }

    head = OpenehrRails::Rm::Composition.latest.find_by!(uid: composition.uid)

    expect(head.context_start_time).to eq(Time.zone.parse("2026-04-15T00:00:00Z"))
  end
end
