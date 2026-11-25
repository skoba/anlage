require "rails_helper"

# R-20261125-1（M2 の出口 I のゲートへの回答、案 B）: 必須の規則を「入れ物を書くなら必須」に改める。
# - 下限 ≥1 の要素は、その要素を含む入れ物（ENTRY と埋め込み CLUSTER）が書かれるときに必須
# - 入れ物が書かれるのは、(1) 配下に値が 1 つでもある、または (2) 自身の下限 ≥1 で、親が書かれる（根の COMPOSITION は常に書かれる）
# - 入れ物の下限が分からない（nil）ときは、任意と見なして黙って通さない（書かれるものとして扱う）
# - 帳票全体で値が 1 つも無ければ保存させない（項目ではなく帳票に付くメッセージ）
RSpec.describe Opt::FormValidator, "入れ物を書くなら必須（R-20261125-1）" do
  RuleTemplate = Struct.new(:fields)

  def container(key, min)
    { "key" => key, "min" => min }
  end

  # 入れ物 entry（0..1）の中に、必須の name と任意の note。入れ物 org（entry の中の CLUSTER）の中に必須の org_name と任意の phone
  def fields(entry_min: 0, org_min: 0)
    entry = container("entry#0", entry_min)
    org = container("org#0", org_min)
    [
      { "name" => "name", "required" => true, "containers" => [ entry ] },
      { "name" => "note", "required" => false, "containers" => [ entry ] },
      { "name" => "org_name", "required" => true, "containers" => [ entry, org ] },
      { "name" => "phone", "required" => false, "containers" => [ entry, org ] },
      { "name" => "other", "required" => false, "containers" => [ container("other#0", 0) ] }
    ]
  end

  def errors_for(values, **mins)
    described_class.call(RuleTemplate.new(fields(**mins)), values).errors
  end

  it "任意（0..1）の入れ物に何も書かなければ、その中の必須の要素は問わない" do
    expect(errors_for({ "other" => "x" })).to eq({})
  end

  it "入れ物に値が 1 つでもあれば、その中の必須の要素が空なら必須項目のエラー" do
    expect(errors_for({ "note" => "x" })).to eq("name" => "必須項目です")
  end

  it "内側の入れ物に値があれば外側の入れ物も書かれる（外側の必須の要素も問う）" do
    expect(errors_for({ "phone" => "03" })).to eq("name" => "必須項目です", "org_name" => "必須項目です")
  end

  it "外側に値があるだけなら、任意の内側の入れ物の必須の要素は問わない" do
    expect(errors_for({ "name" => "A" })).to eq({})
  end

  it "下限 ≥1 の入れ物は、親が書かれれば値が無くても書かれる" do
    expect(errors_for({ "name" => "A" }, org_min: 1)).to eq("org_name" => "必須項目です")
  end

  it "下限 ≥1 の入れ物でも、親が書かれなければ書かれない" do
    expect(errors_for({ "other" => "x" }, org_min: 1)).to eq({})
  end

  it "根の直下の下限 ≥1 の入れ物は、常に書かれる" do
    expect(errors_for({ "other" => "x" }, entry_min: 1)).to eq("name" => "必須項目です")
  end

  it "入れ物の下限が分からない（nil）ときは、書かれるものとして扱う" do
    expect(errors_for({ "other" => "x" }, entry_min: nil)).to eq("name" => "必須項目です")
  end

  it "入れ物の情報が無い field（古い登録）は、これまでどおり下限 ≥1 なら必須" do
    template = RuleTemplate.new([ { "name" => "a", "required" => true }, { "name" => "b", "required" => false } ])
    expect(described_class.call(template, "b" => "x").errors).to eq("a" => "必須項目です")
  end

  it "帳票全体で値が 1 つも無ければ、帳票に付くメッセージで保存させない" do
    expect(errors_for({})).to eq("base" => described_class::EMPTY_FORM_MESSAGE)
    expect(errors_for({ "name" => "", "note" => " " })).to eq("base" => described_class::EMPTY_FORM_MESSAGE)
  end

  it "単位（__units）だけの値は、入力された値に数えない" do
    expect(errors_for({ "note__units" => "mm[Hg]" })).to eq("base" => described_class::EMPTY_FORM_MESSAGE)
  end
end
