require "rails_helper"
require "rake"


# skoba/anlage#47 (1): `rake demo:reset` は既知の初期状態を 1 コマンドで作る（解決形 (b) enhancement）。
# 初期状態 = fixture 5 件が active・pathcards 生成済み・superseded 無し・サンプルのカルテ記録だけがある。
# サンプル（skoba/anlage#144、R-20261125-9 で承認した docs/design/sample-data-plan.md 3 節の表）:
# 架空の患者 9 人（DEMO-01〜09）に 84 件（DEMO-07〜09 は血液内科への紹介の例。設計書 7 節、R-20261126-11）。すべて患者の EHR に結び付き、記録日は 2026-01〜10 の 09:00（日本時間）。
# jp_referral は壇上で登録する（第 1 幕）のでテンプレートは初期状態に含めず、紹介状 5 件は RM グラフにだけ入れる。
# 参照は id ではなく template_id で行う（裁定 2026-10-12）。
RSpec.describe "demo:reset" do
  # template_id は fixture ファイル名と一致しない（patient_blood_pressure.opt の template_id は patient_blood_pressure.v1、実測）
  DEMO_TEMPLATE_IDS = %w[CardiologyEncounter LabResultReport ProblemList bmi_calculation patient_blood_pressure.v1].freeze

  def fixture(name) = Rails.root.join("spec/fixtures/opt/#{name}.opt").read

  def run_task
    Rake::Task["demo:reset"].reenable
    Rake::Task["demo:reset"].invoke
  end

  def rm_compositions = OpenehrRails::Rm::Composition.latest

  it "fixture 5 件を active で登録し pathcards を生成、他のテンプレート・superseded・既存の記録を消してサンプルだけにする（2 回実行しても同じ）" do
    # 乱れた状態: jp_referral が登録済み、ProblemList の旧版が superseded、Composition 1 件（RM グラフ入り）、患者 1 人
    Template.build_from_opt_xml(fixture("jp_referral")).tap(&:save!)
    Template.build_from_opt_xml(fixture("ProblemList")).tap { |t| t.version = "0.9.0"; t.save!; t.supersede! }
    bp = Template.build_from_opt_xml(fixture("patient_blood_pressure")).tap(&:save!)
    commit = Opt::RmCompositionCommitter.call(bp, { "blood_pressure_systolic" => "120", "blood_pressure_diastolic" => "80" })
    bp.compositions.create!(rm_composition: commit.canonical_hash, uid: commit.uid)
    OpenehrRails::Rm::Ehr.create!(ehr_id: SecureRandom.uuid, subject_id: "P-9999", subject_namespace: "anlage")
    expect(OpenehrRails::Rm::Composition.count).to eq(1)

    2.times { run_task }

    expect(Template.active.order(:template_id).pluck(:template_id)).to eq(DEMO_TEMPLATE_IDS.sort)
    expect(Template.where(status: "superseded")).to be_empty
    expect(Template.find_by(template_id: "jp_referral")).to be_nil
    expect(Template.active.map { |t| [ t.template_id, t.version, t.pathcards.present?, t.web_template["form_capability"] ] })
      .to all(match([ a_string_matching(/./), "1.0.0", true, "saveable" ]))
    expect(OpenehrRails::Rm::Ehr.order(:subject_id).pluck(:subject_id, :subject_namespace))
      .to eq((1..9).map { [ format("DEMO-%02d", _1), "anlage" ] })
  end

  describe "サンプルの 84 件（設計書 3 節と 7.3 節の表）" do
    before { run_task }

    it "テンプレートごとの件数: 傷病 13、血圧 v2 11、血圧 v1 6、検査 42、身長体重 7、紹介状 5（RM グラフだけ）" do
      expect(rm_compositions.group(:template_id).count).to eq(
        "ProblemList" => 13, "CardiologyEncounter" => 11, "patient_blood_pressure.v1" => 6,
        "LabResultReport" => 42, "bmi_calculation" => 7, "jp_referral" => 5
      )
      expect(Composition.count).to eq(79)
      expect(rm_compositions.where(uid: Composition.pluck(:uid)).count).to eq(79)
    end

    it "すべて患者の EHR に結び付く。患者ごとの件数は 18・9・9・9・13・7・6・5・8" do
      expect(rm_compositions.where(ehr_id: nil)).to be_empty
      expect(rm_compositions.joins(:ehr).group("openehr_ehrs.subject_id").count)
        .to eq("DEMO-01" => 18, "DEMO-02" => 9, "DEMO-03" => 9, "DEMO-04" => 9, "DEMO-05" => 13, "DEMO-06" => 7,
                "DEMO-07" => 6, "DEMO-08" => 5, "DEMO-09" => 8)
    end

    it "記録日は 2026-01-15〜2026-10-15 の 09:00（日本時間）。OBSERVATION のイベント時刻も同じ" do
      times = rm_compositions.pluck(:context_start_time)

      expect(times).to all(be_present)
      expect(times.minmax).to eq([ Time.zone.parse("2026-01-15T00:00:00Z"), Time.zone.parse("2026-10-15T00:00:00Z") ])
      expect(times.map { _1.in_time_zone("Asia/Tokyo").hour }.uniq).to eq([ 9 ])

      rows = OpenehrRails::Aql::Executor.execute(<<~AQL).rows
        SELECT c/context/start_time/value, o/data[at0001]/events[at0006]/time/value
        FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.blood_pressure.v2]
      AQL
      expect(rows.size).to eq(11)
      expect(rows).to all(satisfy { |start_time, event_time| start_time == event_time })
    end

    it "傷病名 18 件の診断確度とコード（5A11 は DEMO-01 の 2型糖尿病と紹介状だけ）" do
      diagnoses = rm_compositions.includes(:ehr).filter_map do |composition|
        evaluation = composition.to_rm.content.flat_map { _1.respond_to?(:items) ? _1.items : [ _1 ] }
                                .find { _1.archetype_node_id == "openEHR-EHR-EVALUATION.problem_diagnosis.v1" }
        next unless evaluation

        items = evaluation.data.items
        name = items.find { _1.archetype_node_id == "at0002" }.value
        certainty = items.find { _1.archetype_node_id == "at0073" }&.value
        [ composition.ehr.subject_id, composition.template_id, name.value,
          name.respond_to?(:defining_code) ? name.defining_code.code_string : nil, certainty&.defining_code&.code_string ]
      end

      expect(diagnoses).to contain_exactly(
        [ "DEMO-01", "ProblemList", "2型糖尿病", "5A11", "at0076" ],
        [ "DEMO-01", "ProblemList", "糖尿病性腎症", nil, "at0076" ],
        [ "DEMO-01", "ProblemList", "高血圧症", nil, "at0076" ],
        [ "DEMO-01", "jp_referral", "2型糖尿病", "5A11", nil ],
        [ "DEMO-02", "ProblemList", "高血圧症", nil, "at0074" ],
        [ "DEMO-02", "ProblemList", "高血圧症", nil, "at0076" ],
        [ "DEMO-03", "ProblemList", "起立性低血圧", nil, "at0074" ],
        [ "DEMO-03", "ProblemList", "鉄欠乏性貧血", nil, "at0076" ],
        [ "DEMO-04", "ProblemList", "脂質異常症", nil, "at0076" ],
        [ "DEMO-04", "ProblemList", "高血圧症", nil, "at0075" ],
        [ "DEMO-05", "jp_referral", "狭心症", nil, "at0074" ],
        [ "DEMO-05", "ProblemList", "慢性腎臓病", nil, "at0076" ],
        [ "DEMO-05", "ProblemList", "狭心症", nil, "at0074" ],
        [ "DEMO-05", "ProblemList", "2型糖尿病", nil, "at0076" ],
        [ "DEMO-06", "ProblemList", "花粉症", nil, "at0076" ],
        [ "DEMO-07", "jp_referral", "白血病", nil, "at0074" ],
        [ "DEMO-08", "jp_referral", "悪性リンパ腫", nil, "at0074" ],
        [ "DEMO-09", "jp_referral", "多発性骨髄腫", nil, "at0074" ]
      )
    end

    # 血液内科への紹介状 3 通（設計書 7.4 節。R-20261126-11）は、jp_referral の帳票と同じ組み立てで、項目を埋めて入れる。
    # テンプレートは登録しない（保存しない Template で組み立てる。問い 6）
    def elements(node, found = [])
      case node
      when Array then node.each { elements(_1, found) }
      when Hash
        node["_type"] == "ELEMENT" ? found << [ node.dig("name", "value"), node.dig("value", "value") ] : node.each_value { elements(_1, found) }
      end
      found
    end

    it "血液内科への紹介状 3 通は、紹介元・紹介先・診療科・紹介目的・叙述を持ち、記録日は 6〜8 月" do
      referrals = rm_compositions.includes(:ehr).where(template_id: "jp_referral")
                                 .select { _1.ehr.subject_id.in?(%w[DEMO-07 DEMO-08 DEMO-09]) }.sort_by { _1.ehr.subject_id }

      expect(referrals.map { _1.context_start_time.in_time_zone("Asia/Tokyo").to_date.iso8601 })
        .to eq(%w[2026-06-18 2026-07-09 2026-08-20])
      expect(referrals.map { elements(_1.to_canonical_hash["content"]).to_h { |name, value| [ name, value ] }.values_at("サービス名", "紹介目的", "治療経過") })
        .to eq([ [ "外来紹介", "白血球の異常高値と血小板の低値があり、精査加療をお願いします", "未治療" ],
                 [ "外来紹介", "頸部と鼠径部のリンパ節腫脹があり、精査をお願いします", "未治療" ],
                 [ "外来紹介", "腎障害と高タンパク血症があり、精査をお願いします", "未治療" ] ])
      expect(referrals.map { |r| elements(r.to_canonical_hash["content"]).select { _1.first == "名称" }.map(&:last) })
        .to eq([ %w[Bクリニック X病院 血液内科], %w[C内科医院 X病院 血液内科], %w[Aクリニック X病院 血液内科] ])
      expect(referrals.map { |r| elements(r.to_canonical_hash["content"]).to_h["発症日時"] }).to eq([ "2026-06-01T00:00:00Z", "2026-06-08T00:00:00Z", nil ])
      synopses = referrals.map { |r| elements(r.to_canonical_hash["content"]).to_h["症状経過及び検査結果"] }
      expect(synopses[0]).to include("白血球数 48,500/μL（芽球 58%）")
      expect(synopses[1]).to include("左頸部に 2〜3 cm")
      expect(synopses[2]).to include("IgG 5,120 mg/dL")
      expect(Template.find_by(template_id: "jp_referral")).to be_nil
    end
  end

  it "production では実行しない" do
    allow(Rails.env).to receive(:production?).and_return(true)

    expect { run_task }.to raise_error(SystemExit)
    expect(Template.count).to eq(0)
  end

  # skoba/anlage#168（R-20261126-2 の受け入れの台本）: Docker のイメージは production。全データを消して入れ直す操作なので、
  # 明示の環境変数 ANLAGE_ALLOW_DEMO_RESET=1 を与えたときだけ production でも動かす
  context "production で ANLAGE_ALLOW_DEMO_RESET を与えたとき" do
    before { allow(Rails.env).to receive(:production?).and_return(true) }

    around do |example|
      original = ENV["ANLAGE_ALLOW_DEMO_RESET"]
      example.run
    ensure
      ENV["ANLAGE_ALLOW_DEMO_RESET"] = original
    end

    it "1 なら動いて、患者 9 人と 84 件を入れる" do
      ENV["ANLAGE_ALLOW_DEMO_RESET"] = "1"

      run_task

      expect(OpenehrRails::Rm::Ehr.count).to eq(9)
      expect(rm_compositions.count).to eq(84)
    end

    it "1 以外（true など）では、これまでどおり止まる" do
      ENV["ANLAGE_ALLOW_DEMO_RESET"] = "true"

      expect { run_task }.to raise_error(SystemExit)
      expect(Template.count).to eq(0)
    end
  end
end
