require "rails_helper"
require "rake"

Rails.application.load_tasks

# skoba/anlage#47 (1): `rake demo:reset` は既知の初期状態を 1 コマンドで作る（解決形 (b) enhancement）。
# 初期状態 = fixture 5 件が active・pathcards 生成済み・superseded 無し・サンプルのカルテ記録だけがある。
# サンプル（裁定 D 2026-10-12・裁定 2026-10-20）: ProblemList 2（ICD-11 コード付き 1・自由記述 1）、
# CardiologyEncounter 1、LabResultReport 1（数値 > 50）、bmi 1（170/65）、jp_referral 1（ICD-11 コード付き）。
# jp_referral は壇上で登録する（第 1 幕）のでテンプレートは初期状態に含めず、サンプルは RM グラフにだけ入れる。
# 参照は id ではなく template_id で行う（裁定 2026-10-12）。
RSpec.describe "demo:reset" do
  # template_id は fixture ファイル名と一致しない（patient_blood_pressure.opt の template_id は patient_blood_pressure.v1、実測）
  DEMO_TEMPLATE_IDS = %w[CardiologyEncounter LabResultReport ProblemList bmi_calculation patient_blood_pressure.v1].freeze

  def fixture(name) = Rails.root.join("spec/fixtures/opt/#{name}.opt").read

  def run_task
    Rake::Task["demo:reset"].reenable
    Rake::Task["demo:reset"].invoke
  end

  it "fixture 5 件を active で登録し pathcards を生成、他のテンプレート・superseded・既存の記録を消してサンプルだけにする（2 回実行しても同じ）" do
    # 乱れた状態: jp_referral が登録済み、ProblemList の旧版が superseded、Composition 1 件（RM グラフ入り）
    Template.build_from_opt_xml(fixture("jp_referral")).tap(&:save!)
    Template.build_from_opt_xml(fixture("ProblemList")).tap { |t| t.version = "0.9.0"; t.save!; t.supersede! }
    bp = Template.build_from_opt_xml(fixture("patient_blood_pressure")).tap(&:save!)
    commit = Opt::RmCompositionCommitter.call(bp, { "blood_pressure_systolic" => "120", "blood_pressure_diastolic" => "80" })
    bp.compositions.create!(rm_composition: commit.canonical_hash, uid: commit.uid)
    expect(OpenehrRails::Rm::Composition.count).to eq(1)

    2.times { run_task }

    expect(Template.active.order(:template_id).pluck(:template_id)).to eq(DEMO_TEMPLATE_IDS.sort)
    expect(Template.where(status: "superseded")).to be_empty
    expect(Template.find_by(template_id: "jp_referral")).to be_nil
    expect(Template.active.map { |t| [ t.template_id, t.version, t.pathcards.present?, t.web_template["form_capability"] ] })
      .to all(match([ a_string_matching(/./), "1.0.0", true, "saveable" ]))
    expect(Composition.joins(:template).order("templates.template_id").pluck("templates.template_id"))
      .to eq(%w[CardiologyEncounter LabResultReport ProblemList ProblemList bmi_calculation])
    # RM 側は Composition 名で見る（フォーム経路の Composition はルートに archetype_details を持たず
    # template_id 列が nil になる。既存の欠陥、log R10）
    expect(OpenehrRails::Rm::Composition.order(:name_value).pluck(:name_value))
      .to eq(%w[CardiologyEncounter LabResultReport ProblemList ProblemList bmi_calculation jp_referral])
    expect(OpenehrRails::Rm::Composition.where(uid: Composition.pluck(:uid)).count).to eq(5)
  end

  it "傷病名のサンプルは ICD-11 コード付き（ProblemList 1・jp_referral 1）と自由記述（ProblemList 1）" do
    run_task

    diagnoses = OpenehrRails::Rm::Composition.order(:name_value).map do |composition|
      evaluation = composition.to_rm.content.flat_map { _1.respond_to?(:items) ? _1.items : [ _1 ] }
                              .find { _1.archetype_node_id == "openEHR-EHR-EVALUATION.problem_diagnosis.v1" }
      next unless evaluation

      value = evaluation.data.items.find { _1.archetype_node_id == "at0002" }.value
      [ composition.name_value, value.value, value.respond_to?(:defining_code) ? value.defining_code.code_string : nil ]
    end.compact

    expect(diagnoses).to contain_exactly(
      [ "ProblemList", "2型糖尿病", "5A11" ], [ "ProblemList", "高血圧症", nil ], [ "jp_referral", "2型糖尿病", "5A11" ]
    )
  end

  it "production では実行しない" do
    allow(Rails.env).to receive(:production?).and_return(true)

    expect { run_task }.to raise_error(SystemExit)
    expect(Template.count).to eq(0)
  end
end
