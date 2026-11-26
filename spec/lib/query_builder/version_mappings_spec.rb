require "rails_helper"

# アーキタイプの版の対応（docs/design/s2-cross-version-plan.md 3 節、skoba/anlage#154、R-20261125-10）。
# 候補は自動で挙げるが、問い合わせに使うのは人間がレビューした行だけ。アーキタイプ ID と at-code は実物（spec/fixtures/opt/）。
RSpec.describe "アーキタイプの版の対応" do
  VM_BP = "openEHR-EHR-OBSERVATION.blood_pressure".freeze

  def register(*fixture_names)
    fixture_names.each do |fixture_name|
      template = Template.build_from_opt_xml(Rails.root.join("spec/fixtures/opt/#{fixture_name}.opt").read)
      template.pathcards = Opt::PathcardExtractor.call(template).cards
      template.save!
    end
  end

  describe QueryBuilder::VersionCandidates do
    it "血圧の v1 と v2 の収縮期（at0004）・拡張期（at0005）が候補に挙がる。単位も値の範囲も同じなので、印は付かない" do
      register("CardiologyEncounter", "patient_blood_pressure", "ProblemList")

      candidates = described_class.call(QueryBuilder::Corpus.active)

      expect(candidates.map { |c| [ c.concept, c.at_code, c.versions, c.rm_type, c.differences ] }).to eq([
        [ VM_BP, "at0004", %w[v1 v2], "DV_QUANTITY", [] ],
        [ VM_BP, "at0005", %w[v1 v2], "DV_QUANTITY", [] ]
      ])
      expect(candidates.first.labels).to eq("v1" => "Systolic", "v2" => "収縮期")
      expect(candidates.first.path).to eq("data[at0001]/events[at0006]/data[at0003]/items[at0004]/value")
    end

    it "版が 1 つしか索引に無い項目は、候補にしない" do
      register("CardiologyEncounter", "ProblemList")

      expect(described_class.call(QueryBuilder::Corpus.active)).to eq([])
    end

    it "単位か値の範囲が違う組には印が付く。at-code・パス・型のどれかが違えば、候補にしない" do
      register("CardiologyEncounter", "patient_blood_pressure")
      cards = QueryBuilder::Corpus.active.cards.map(&:deep_dup)
      v1 = cards.select { |card| card.dig("identity", "archetype_id") == "#{VM_BP}.v1" }
      v1.find { |card| card.dig("identity", "at_code") == "at0004" }["constraints"]["value"]["units"] = "kPa"
      v1.find { |card| card.dig("identity", "at_code") == "at0005" }["semantics"]["rm_type"] = "DV_COUNT"

      candidates = described_class.call(QueryBuilder::Corpus.new(cards))

      expect(candidates.map { |c| [ c.at_code, c.differences ] }).to eq([ [ "at0004", [ "単位（v1: kPa、v2: mm[Hg]）" ] ] ])
    end
  end

  describe QueryBuilder::VersionMappings do
    def row(at_code, **options)
      { "concept" => VM_BP, "at_code" => at_code, "versions" => %w[v1 v2], "source" => "spec",
        "reviewed_by" => "Kobayashi, Shinji", "reviewed_at" => Date.new(2026, 11, 25) }.merge(options.transform_keys(&:to_s))
    end

    def card(version, at_code)
      { "identity" => { "archetype_id" => "#{VM_BP}.#{version}", "at_code" => at_code } }
    end

    it "active の行がある項目は、同じものと確かめた版のアーキタイプ ID を返す。行の無い項目と、行に無い版は nil" do
      mappings = described_class.new([ row("at0004") ])

      expect(mappings.archetype_ids(card("v2", "at0004"))).to eq([ "#{VM_BP}.v1", "#{VM_BP}.v2" ])
      expect(mappings.archetype_ids(card("v1", "at0004"))).to eq([ "#{VM_BP}.v1", "#{VM_BP}.v2" ])
      expect(mappings.archetype_ids(card("v2", "at0005"))).to be_nil
      expect(mappings.archetype_ids(card("v3", "at0004"))).to be_nil
    end

    it "pending の行（候補のまま）は使わない。レビューの記録が無くても読める" do
      mappings = described_class.new([ row("at0004", status: "pending").except("reviewed_by", "reviewed_at") ])

      expect(mappings.archetype_ids(card("v2", "at0004"))).to be_nil
      expect(mappings.rows.map { |r| [ r.at_code, r.status ] }).to eq([ [ "at0004", :pending ] ])
    end

    it "形式の誤りは読み込みで止める（active なのにレビューの記録が無い、版が 1 つ、版の書き方、同じ項目の重複、知らない status）" do
      {
        [ row("at0004").except("reviewed_by") ] => /at0004.*reviewed_by/,
        [ row("at0004", versions: %w[v2]) ] => /at0004.*versions/,
        [ row("at0004", versions: %w[1 2]) ] => /at0004.*versions/,
        [ row("at0004").except("concept") ] => /concept/,
        [ row("at0004").except("source") ] => /at0004.*source/,
        [ row("at0004", status: "draft") ] => /at0004.*status/,
        [ row("at0004"), row("at0004") ] => /同じ項目/
      }.each do |rows, message|
        expect { described_class.new(rows) }.to raise_error(described_class::InvalidTable, message)
      end
    end

    # リポジトリの表（config/version_mappings.yml）。最初の 2 行は、レビューを経て active になった（R-20261125-11。小林、2026-11-25）。
    # 行を変えたら、この例も同じコミットで直す
    it "リポジトリの表: 血圧の収縮期と拡張期の 2 行が active で、レビューの記録と、確かめた範囲の注記を持つ" do
      rows = described_class.default.rows

      expect(rows.map { |r| [ r.concept, r.at_code, r.versions, r.status ] })
        .to eq([ [ VM_BP, "at0004", %w[v1 v2], :active ], [ VM_BP, "at0005", %w[v1 v2], :active ] ])
      expect(rows.map { |r| [ r.reviewed_by, r.reviewed_at ] }.uniq).to eq([ [ "Kobayashi, Shinji", Date.new(2026, 11, 25) ] ])
      expect(rows.map(&:note)).to all(include("at-code、パス、型、単位、値の範囲が同じ").and(include("改訂の内容は、セッションは比べていない")))
      expect(described_class.default.archetype_ids(card("v2", "at0004"))).to eq([ "#{VM_BP}.v1", "#{VM_BP}.v2" ])
    end
  end
end
