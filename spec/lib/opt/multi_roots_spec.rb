require "rails_helper"

# skoba/anlage#117（M2 の C）: 同じアーキタイプの複数ルートを区別する。
# 実物 fixture: jp_referral.opt v0.2。紹介元／紹介先の organisation（同じ path に 2 つ）、紹介先の中の診療科（organisation の入れ子）、
# 医師／担当医の person、2 つの clinical_synopsis（症状経過及び検査結果／治療経過）。名前は OPT の term_definitions の実測。
RSpec.describe "同じアーキタイプの複数ルート（#117）" do
  let(:template) { Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/jp_referral.opt").read).tap(&:save!).reload }

  def field_named(name)
    template.fields.find { |field| field["name"] == name } || raise("no field #{name}")
  end

  describe "web_template の field" do
    it "field 名が衝突しない。2 つめ以降は文書順に _2・_3 を付ける" do
      names = template.fields.map { |field| field["name"] }

      expect(names).to eq(names.uniq)
      expect(names).to include("organisation_at0001", "organisation_at0001_2", "organisation_at0001_3",
                               "person_at0001", "person_at0001_2", "clinical_synopsis", "clinical_synopsis_2")
    end

    it "埋め込みルートの項目は、属するルート（インスタンス）のテンプレート上の名前を root_label に持つ" do
      expect(%w[organisation_at0001 organisation_at0001_2 organisation_at0001_3 person_at0001 person_at0001_2].map { |name| field_named(name)["root_label"] })
        .to eq(%w[紹介元医療機関 紹介先医療機関 診療科 医師 担当医])
    end

    it "2 つの clinical_synopsis は、それぞれのルートの名前でラベルされる" do
      expect(%w[clinical_synopsis clinical_synopsis_2].map { |name| field_named(name)["label"] }).to eq(%w[症状経過及び検査結果 治療経過])
    end

    it "jp_referral の帳票は保存可能になる（SECTION・INSTRUCTION・複数ルートがそろった）" do
      expect(template.web_template.values_at("form_capability", "form_capability_reason")).to eq([ "saveable", nil ])
    end
  end

  describe "保存（CompositionBuilder）" do
    let(:values) do
      {
        "organisation_at0001" => "A病院", "organisation_at0001_2" => "X病院", "organisation_at0001_3" => "内科",
        "clinical_synopsis" => "HbA1c 8.2%", "clinical_synopsis_2" => "メトホルミン開始"
      }
    end
    let(:section) { Opt::CompositionBuilder.new(template, values).build.content.first }

    it "紹介元と紹介先の organisation を別々の CLUSTER に入れ、診療科は紹介先の中に入れる" do
      protocol = section.items.find { |entry| entry.is_a?(OpenEHR::RM::Composition::Content::Entry::Instruction) }.protocol
      summary = ->(cluster) { [ cluster.name.value, cluster.items.map { |item| item.respond_to?(:value) ? item.value.value : summary.(item) } ] }

      expect(protocol.items.map(&summary)).to eq([
        [ "紹介元医療機関", [ "A病院" ] ],
        [ "紹介先医療機関", [ "X病院", [ "診療科", [ "内科" ] ] ] ]
      ])
    end

    it "2 つの clinical_synopsis に別の値を入れると、2 つの EVALUATION に分かれて入る" do
      synopses = section.items.select { |entry| entry.archetype_node_id == "openEHR-EHR-EVALUATION.clinical_synopsis.v1" }

      expect(synopses.map { |entry| [ entry.name.value, entry.data.items.map { |item| item.value.value } ] })
        .to eq([ [ "症状経過及び検査結果", [ "HbA1c 8.2%" ] ], [ "治療経過", [ "メトホルミン開始" ] ] ])
    end

    it "保存して、紹介先医療機関を name 述語の AQL で引ける" do
      Opt::RmCompositionCommitter.call(template, values)

      result = OpenehrRails::Aql::Executor.execute(<<~AQL)
        SELECT i/protocol[at0008]/items[openEHR-EHR-CLUSTER.organisation.v1, '紹介先医療機関']/items[at0001]/value/value
        FROM EHR e CONTAINS COMPOSITION c CONTAINS INSTRUCTION i[openEHR-EHR-INSTRUCTION.service_request.v1]
      AQL
      expect(result.rows).to eq([ [ "X病院" ] ])
    end
  end
end
