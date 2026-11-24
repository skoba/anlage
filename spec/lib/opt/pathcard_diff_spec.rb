require "rails_helper"

# skoba/anlage#100（M3 の W5）: 2 つの版のパスカードの差分。キーは identity.path（スキーマ v1.2。読むだけ）。
# fixture: 実物の patient_blood_pressure.opt と、そこからラベルを 1 つ置き換えた版（実物からの導出）。
RSpec.describe Opt::PathcardDiff do
  let(:source_xml) { Rails.root.join("spec/fixtures/opt/patient_blood_pressure.opt").read }

  def cards_of(xml)
    template = Template.build_from_opt_xml(xml)
    Opt::PathcardExtractor.call(template).cards.map(&:deep_stringify_keys)
  end

  let(:old_cards) { cards_of(source_xml) }
  let(:new_cards) { cards_of(source_xml.sub("Systolic", "Systolic Pressure")) }

  it "同じパスカードどうしなら、差分は無い" do
    diff = described_class.call(old_cards, old_cards)

    expect(diff.any_changes?).to be(false)
    expect([ diff.added, diff.removed, diff.changed ]).to all(be_empty)
  end

  it "ラベルが変わったカードを、path と、変わった観点（ラベル）と、前後の値で返す" do
    diff = described_class.call(old_cards, new_cards)

    expect(diff.added).to be_empty
    expect(diff.removed).to be_empty
    expect(diff.changed.size).to eq(1)
    change = diff.changed.first
    expect(change["path"]).to end_with("/items[at0004]/value")
    expect(change["changes"]).to eq([ { "aspect" => "labels", "before" => [ "Systolic" ], "after" => [ "Systolic Pressure" ] } ])
  end

  it "片方にしか無いカードを、追加・削除として返す" do
    systolic = ->(card) { card.dig("semantics", "labels").any? { |label| label["text"] == "Systolic" } }
    dropped = old_cards.reject(&systolic)
    expect(old_cards.size - dropped.size).to eq(1)

    diff = described_class.call(old_cards, dropped)
    expect(diff.removed.map { |card| card.dig("semantics", "labels", 0, "text") }).to eq([ "Systolic" ])
    expect(diff.added).to be_empty
    expect(diff.changed).to be_empty

    reverse = described_class.call(dropped, old_cards)
    expect(reverse.added.map { |card| card.dig("semantics", "labels", 0, "text") }).to eq([ "Systolic" ])
  end

  it "パスカードが無い版（nil）は、空として扱う" do
    expect(described_class.call(nil, old_cards).added.size).to eq(old_cards.size)
  end
end
