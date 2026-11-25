require "rails_helper"

# 別名表（S3 の段 D。docs/design/s3-search-plan.md 3.1、skoba/anlage#152、R-20261125-8）。
# 表は人間がレビューした行だけを持つ。ここでは読み込みと引き方を確かめる。アーキタイプ ID と at-code は実物。
RSpec.describe Opt::SearchAliases do
  SA_PD = "openEHR-EHR-EVALUATION.problem_diagnosis.v1".freeze
  SA_BMI = "openEHR-EHR-OBSERVATION.body_mass_index.v2".freeze

  def row(term, **options)
    { "term" => term, "relation" => "alias", "targets" => [ { "archetype_id" => SA_PD, "at_code" => "at0002" } ],
      "source" => "v1 q05", "reviewed_by" => "Kobayashi, Shinji", "reviewed_at" => Date.new(2026, 11, 25) }.merge(options.transform_keys(&:to_s))
  end

  def table(*rows) = described_class.new(rows)

  describe "引き方（語の全体が一致したときだけ）" do
    let(:aliases) { table(row("既往", targets: [ { "archetype_id" => SA_PD, "at_code" => "at0002" }, { "archetype_id" => SA_PD } ]), row("BMI", targets: [ { "archetype_id" => SA_BMI } ])) }

    it "語の全体が一致すれば、その行の対応先を順に返す。at_code を省いた対応先は at_code が nil" do
      expect(aliases.lookup("既往")).to have_attributes(
        term: "既往", relation: :alias, targets: [ { archetype_id: SA_PD, at_code: "at0002" }, { archetype_id: SA_PD, at_code: nil } ]
      )
    end

    it "部分一致では引かない（「既往歴」「既往症の有無」は「既往」の行に当たらない）" do
      expect(aliases.lookup("既往歴")).to be_nil
      expect(aliases.lookup("既往症の有無")).to be_nil
    end

    it "前後の空白、全角と半角、英字の大小は区別しない" do
      expect([ " BMI ", "ｂｍｉ", "Bmi", "ＢＭＩ" ].map { |query| aliases.lookup(query)&.term }).to eq(%w[BMI BMI BMI BMI])
    end

    it "保留（pending）の行は引かない。terms には、保留でない行の語だけが入る" do
      aliases = table(row("既往"), row("既往歴", status: "pending", pending_until: "story を持つテンプレートが索引に入る"))

      expect(aliases.lookup("既往歴")).to be_nil
      expect(aliases.terms).to eq([ "既往" ])
      expect(aliases.rows.map { |r| [ r.term, r.status ] }).to eq([ [ "既往", :active ], [ "既往歴", :pending ] ])
    end

    it "対応させない行（exclude）も引ける" do
      expect(table(row("体格指数", relation: "exclude", targets: [ { "archetype_id" => SA_BMI } ])).lookup("体格指数")).to have_attributes(relation: :exclude)
    end

    it "空の表（none）は何も引かない" do
      expect(described_class.none.lookup("BMI")).to be_nil
    end
  end

  describe "形式の誤りは読み込みで止める" do
    it "語・対応先・出どころ・レビューの記録が無い行、知らない relation と status、同じ語の重複" do
      {
        row("病名").except("term") => /term/,
        row("病名", targets: []) => /病名.*targets/,
        row("病名", targets: [ { "at_code" => "at0002" } ]) => /病名.*archetype_id/,
        row("病名").except("source") => /病名.*source/,
        row("病名").except("reviewed_by") => /病名.*reviewed_by/,
        row("病名").except("reviewed_at") => /病名.*reviewed_at/,
        row("病名", relation: "synonym") => /病名.*relation/,
        row("病名", status: "draft") => /病名.*status/
      }.each do |bad, message|
        expect { table(bad) }.to raise_error(described_class::InvalidTable, message)
      end

      expect { table(row("BMI"), row("ｂｍｉ")) }.to raise_error(described_class::InvalidTable, /同じ語/)
    end
  end

  # リポジトリの表（config/search_aliases.yml）。行は R-20261125-8 でレビューされたもの。行を変えたら、この例も同じコミットで直す
  describe "リポジトリの表" do
    subject(:aliases) { described_class.default }

    it "対応させる 6 行、対応させない 4 行、保留 1 行。すべてレビューの記録を持つ" do
      by_kind = aliases.rows.group_by { |r| r.status == :pending ? :pending : r.relation }.transform_values { |rows| rows.map(&:term) }

      expect(by_kind).to eq(alias: %w[BMI 病名 疾患名 既往 臨床検査 傷病名], exclude: %w[体格指数 肥満判定 肥満度判定 判定], pending: %w[既往歴])
      expect(aliases.rows.map { |r| [ r.reviewed_by, r.reviewed_at ] }.uniq).to eq([ [ "Kobayashi, Shinji", Date.new(2026, 11, 25) ] ])
      expect(aliases.rows.map(&:source)).to all(be_present)
    end

    it "「既往」で最初に出す対応先は、プロブレム・診断名（at0002）" do
      expect(aliases.lookup("既往").targets).to eq([ { archetype_id: SA_PD, at_code: "at0002" }, { archetype_id: SA_PD, at_code: nil } ])
    end

    it "対応先のアーキタイプ ID と at-code は、fixture のカードに実在する" do
      known = Rails.root.glob("spec/fixtures/opt/{ProblemList,LabResultReport,bmi_calculation,jp_referral}.opt").flat_map do |path|
        Opt::PathcardExtractor.call(Template.build_from_opt_xml(path.read)).cards.map { |card| card.fetch("identity").values_at("archetype_id", "at_code") }
      end
      targets = aliases.rows.flat_map(&:targets)

      expect(targets.reject { |target| known.any? { |archetype_id, at_code| archetype_id == target[:archetype_id] && [ nil, at_code ].include?(target[:at_code]) } }).to be_empty
    end
  end
end
