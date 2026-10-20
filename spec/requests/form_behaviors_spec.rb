require "rails_helper"

# skoba/anlage#47 変更 4: サーバが権威。クライアントの計算値（や改ざん）にかかわらず、保存される
# Composition には config/form_behaviors.yml の再計算値が入る。
RSpec.describe "POST /compositions/bmi_calculation（form_behaviors）", type: :request do
  let!(:template) do
    Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/bmi_calculation.opt").read).tap(&:save!)
  end

  # canonical JSON 中の ELEMENT を archetype_node_id ではなく値の形で拾う（パスを推測しない）
  def element_values(node, found = [])
    case node
    when Hash
      found << node["value"] if node["_type"] == "ELEMENT"
      node.each_value { element_values(_1, found) }
    when Array then node.each { element_values(_1, found) }
    end
    found
  end

  it "送られた BMI 99 は再計算値 22.5 で上書きされ、空欄の判定は「普通体重」で埋まって保存される" do
    post template_compositions_path(template.template_id), params: {
      values: { "height" => "170", "body_weight" => "65", "body_mass_index" => "99", "body_mass_index_at0013" => "" }
    }

    expect(response).to redirect_to(composition_path(Composition.last))
    values = element_values(Composition.last.rm_composition)
    expect(values.filter_map { _1["magnitude"] }).to contain_exactly(170.0, 65.0, 22.5)
    expect(values.filter_map { _1["value"] }).to eq([ "普通体重" ])
  end

  it "帳票は振る舞いの宣言（yml の写し）をクライアントへ渡す" do
    get form_path(template.template_id)

    form = Nokogiri::HTML(response.body).at_css("form[data-controller~='form-behaviors']")
    expect(JSON.parse(form["data-form-behaviors-rules-value"])).to eq(Opt::FormBehaviors.rules_for("bmi_calculation"))
    expect(form["data-action"]).to include("input->form-behaviors#recalculate")
  end

  it "振る舞いを宣言していない帳票には controller を付けない" do
    problem_list = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!)
    get form_path(problem_list.template_id)

    expect(Nokogiri::HTML(response.body).at_css("[data-controller~='form-behaviors']")).to be_nil
  end
end
