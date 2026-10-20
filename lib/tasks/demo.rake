# デモ状態管理（skoba/anlage#47 (1)、裁定 2026-10-12）。リハ・本番で繰り返し使う「既知の初期状態」を
# 1 コマンドで作る:
#   - Composition・RM グラフ（openehr_rm_*／openehr_ehrs）を空にする
#   - 登録テンプレートを全て消し、fixture 5 件を登録経路と同じ手順（build_from_opt_xml →
#     PathcardExtractor → save）で active に登録する。web_template と pathcards は登録時に新規導出されるので、
#     `templates:rebuild_web_template`／`pathcards:backfill` を別に回す必要はない
#   - jp_referral は壇上で登録する（第 1 幕）ので初期状態に含めない
#   - サンプルのカルテ記録を入れる（Demo::SampleCompositions。jp_referral のサンプルは RM グラフにだけ入る）
# 参照は id ではなく template_id で行う（dev DB の id は環境ごとに違う）。
namespace :demo do
  DEMO_FIXTURES = %w[CardiologyEncounter LabResultReport ProblemList bmi_calculation patient_blood_pressure].freeze
  RM_TABLES_IN_DELETE_ORDER = lambda do
    [ OpenehrRails::Rm::DataValue, OpenehrRails::Rm::Node, OpenehrRails::Rm::Version,
      OpenehrRails::Rm::Composition, OpenehrRails::Rm::Contribution, OpenehrRails::Rm::Ehr ]
  end

  desc "Reset the demo state: purge compositions and the RM graph, re-register the 5 fixture templates (not jp_referral), load sample compositions"
  task reset: :environment do
    abort "demo:reset は production では実行しない" if Rails.env.production?

    ActiveRecord::Base.transaction do
      RM_TABLES_IN_DELETE_ORDER.call.each(&:delete_all)
      Composition.delete_all
      Template.delete_all

      DEMO_FIXTURES.each do |name|
        template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{name}.opt").read)
        template.pathcards = Opt::PathcardExtractor.call(template).cards
        template.save!
        puts "#{template.template_id} v#{template.version}: #{template.fields.size} field(s), " \
             "#{template.pathcards.size} pathcard(s), #{template.web_template['form_capability']}"
      end
      Demo::SampleCompositions.load!
    end
    puts "templates=#{Template.active.count} compositions=#{Composition.count} rm_compositions=#{OpenehrRails::Rm::Composition.count}"
  end
end
