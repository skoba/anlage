require "rails_helper"
require "rake"

Rails.application.load_tasks

# skoba/anlage#33 裁定 C: 登録済みテンプレートの web_template は登録時に固定され、同一
# checksum の再投入は「already registered」で再構築されない。pathcards:backfill と対の
# 運用ツールとして、全テンプレートの web_template を source_xml から再構築する。
RSpec.describe "templates:rebuild_web_template" do
  it "全テンプレートの field を再導出し（input_kind が付く）、checksum と pathcards は変えない" do
    template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read)
    template.pathcards = [ { "schema_version" => "1.2" } ]
    template.save!
    template.update_column(:web_template, template.web_template.deep_dup.tap { |wt| wt["entries"].each { |e| e["fields"].each { |f| f.delete("input_kind") } } })

    Rake::Task["templates:rebuild_web_template"].reenable
    Rake::Task["templates:rebuild_web_template"].invoke

    template.reload
    expect(template.fields.find { |f| f["name"] == "problem_diagnosis_at0002" }["input_kind"]).to eq("coded_free")
    expect(template.pathcards).to eq([ { "schema_version" => "1.2" } ])
  end
end
