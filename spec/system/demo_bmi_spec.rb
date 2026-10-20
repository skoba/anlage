require "rails_helper"

# 台本 2 幕（skoba/anlage#47 6 節）: 身長・体重を入れると BMI と判定が即時に出る（クライアント計算）→
# 保存すると同じ値がサーバの再計算で保存される（権威はサーバ、Opt::FormBehaviors）。
# 評価器は Ruby／JS の 2 実装なので、yml の式例が画面でも Ruby と同じ値になることをここで固定する
# （Ruby 側は spec/lib/opt/form_behaviors_spec.rb）。
RSpec.describe "デモ動線: BMI の自動計算（実ブラウザ）", type: :system, js: true do
  let!(:template) do
    Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/bmi_calculation.opt").read).tap(&:save!)
  end

  it "身長 170・体重 65 で BMI 22.5（readonly）と判定「普通体重」が即時に出て、保存後の AQL で引ける" do
    visit form_path(template.template_id)

    fill_in "field_height", with: "170"
    fill_in "field_body_weight", with: "65"

    expect(page).to have_field("field_body_mass_index", with: "22.5", readonly: true)
    expect(page).to have_field("field_body_mass_index_at0013", with: "普通体重")

    click_button "保存"
    expect(page).to have_css("#flash", text: "保存しました")

    query = <<~AQL
      SELECT o/data[at0001]/events[at0002]/data[at0003]/items[at0004]/value/magnitude AS height
      FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.height.v2]
      WHERE o/data[at0001]/events[at0002]/data[at0003]/items[at0004]/value/magnitude > 170
    AQL
    expect(OpenehrRails::Aql::Executor.execute(query).rows).to eq([])
    expect(OpenehrRails::Aql::Executor.execute(query.sub("> 170", ">= 170")).rows).to eq([ [ 170.0 ] ])
  end

  # 裁定 C: 人間が判定を書き換えたら、その後に身長を直しても提案で上書きしない（編集済みフラグ）
  it "判定を手で直した後に身長を直しても、判定は手で直した値のまま保存される" do
    visit form_path(template.template_id)

    fill_in "field_height", with: "170"
    fill_in "field_body_weight", with: "65"
    expect(page).to have_field("field_body_mass_index_at0013", with: "普通体重")

    fill_in "field_body_mass_index_at0013", with: "肥満（1度）"
    fill_in "field_height", with: "180"

    expect(page).to have_field("field_body_mass_index", with: "20.1")
    expect(page).to have_field("field_body_mass_index_at0013", with: "肥満（1度）")

    click_button "保存"
    expect(page).to have_css("#flash", text: "保存しました")
    saved = Composition.last.rm_composition.to_json
    expect(saved).to include("肥満（1度）")
    expect(saved).not_to include("普通体重")
  end
end
