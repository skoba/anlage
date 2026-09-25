require "rails_helper"

RSpec.describe Template, type: :model do
  let(:opt_xml) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt").read }

  describe ".build_from_opt_xml" do
    it "parses template_id, checksum and a web_template with entries/fields from the OPT" do
      template = Template.build_from_opt_xml(opt_xml)

      expect(template.template_id).to be_present
      expect(template.version).to eq("1.0.0")
      expect(template.status).to eq("active")
      expect(template.checksum).to eq(Digest::SHA256.hexdigest(opt_xml))
      expect(template.web_template["entries"]).not_to be_empty
      expect(template.fields).not_to be_empty
      expect(template.fields.first).to include("name", "label", "path", "rm_type", "column_type")
    end

    it "is not yet persisted" do
      template = Template.build_from_opt_xml(opt_xml)
      expect(template).not_to be_persisted
    end

    it "raises InvalidTemplate for XML that isn't an operational template" do
      expect { Template.build_from_opt_xml("<not-an-opt/>") }
        .to raise_error(Template::InvalidTemplate)
    end
  end

  describe "checksum uniqueness" do
    it "rejects a second record with the same source_xml checksum" do
      Template.build_from_opt_xml(opt_xml).save!
      duplicate = Template.build_from_opt_xml(opt_xml)
      duplicate.version = "2.0.0" # different version, same content -> still same checksum

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:checksum]).to be_present
    end
  end

  describe ".find_by_checksum" do
    it "finds an already-registered template by the checksum of its source_xml" do
      saved = Template.build_from_opt_xml(opt_xml).tap(&:save!)
      expect(Template.find_by_checksum(opt_xml)).to eq(saved)
    end

    it "returns nil for content that has not been registered" do
      expect(Template.find_by_checksum("<unregistered/>")).to be_nil
    end
  end

  describe "[template_id, version] uniqueness" do
    it "allows a new version of an already-registered template_id" do
      first = Template.build_from_opt_xml(opt_xml).tap(&:save!)
      second = first.dup
      second.version = "1.1.0"
      second.checksum = "different-checksum-for-spec"

      expect(second).to be_valid
    end
  end
end

# skoba/anlage#33: web_template の field に rm_type_alternatives（additive）と input_kind
# （登録時に一度だけ導出する方針属性）を付ける。rm_type は gem の値のまま。
RSpec.describe Template, "#33 input_kind と rm_type_alternatives" do
  def field_of(fixture, name)
    Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture}").read).fields.find { |f| f["name"] == name }
  end

  it "ProblemList の傷病名は rm_type DV_CODED_TEXT のまま、代替 [DV_TEXT, DV_CODED_TEXT]・input_kind coded_free" do
    field = field_of("ProblemList.opt", "problem_diagnosis_at0002")

    expect(field["rm_type"]).to eq("DV_CODED_TEXT")
    expect(field["rm_type_alternatives"]).to eq([ "DV_TEXT", "DV_CODED_TEXT" ])
    expect(field["input_kind"]).to eq("coded_free")
  end

  it "診断確度（ローカル code_list）は select、数量は number、テキストは text" do
    expect(field_of("ProblemList.opt", "problem_diagnosis_at0073")["input_kind"]).to eq("select")
    expect(field_of("patient_blood_pressure.opt", "blood_pressure_systolic")["input_kind"]).to eq("number")
    expect(field_of("jp_referral.opt", "story")["input_kind"]).to eq("text")
  end

  it "#rebuild_web_template! は保存済みテンプレートの field を再導出し checksum を変えない" do
    template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).tap(&:save!)
    template.update_column(:web_template, template.web_template.deep_dup.tap { |wt| wt["entries"].each { |e| e["fields"].each { |f| f.delete("input_kind") } } })
    expect(template.reload.fields.first).not_to have_key("input_kind")

    expect { template.rebuild_web_template! }.not_to(change { template.reload.checksum })
    expect(template.reload.fields.find { |f| f["name"] == "problem_diagnosis_at0002" }["input_kind"]).to eq("coded_free")
  end
end

# skoba/anlage#34: gem の required は「entry が必須 かつ 要素が必須」なので 0..1 の entry
# 配下では常に false。Anlage 側で要素の occurrences 下限（OPT）から required を導出する。
RSpec.describe Template, "#34 required は要素の occurrences 下限から導出" do
  it "ProblemList の傷病名 at0002（1..1）は required、発症日時 at0077（0..1）は任意" do
    fields = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/ProblemList.opt").read).fields

    expect(fields.find { |f| f["name"] == "problem_diagnosis_at0002" }).to include("required" => true, "min_occurrences" => 1)
    expect(fields.find { |f| f["name"] == "problem_diagnosis_at0077" }).to include("required" => false, "min_occurrences" => 0)
  end
end
