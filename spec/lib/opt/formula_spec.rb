require "rails_helper"

# skoba/anlage#47 変更 4: config/form_behaviors.yml の式を評価する安全サブセット（GDL2 互換の範囲）。
# 数値・識別子（inputs 名）・+ - * / ^・括弧・round(x, n)・比較 < <= > >= == !=。eval は使わない。
RSpec.describe Opt::Formula do
  def evaluate(expression, variables = {}) = described_class.evaluate(expression, variables)

  describe "四則と累乗" do
    it "優先順位は ^ > * / > + -、^ は右結合、括弧で上書きできる" do
      expect(evaluate("1 + 2 * 3")).to eq(7)
      expect(evaluate("(1 + 2) * 3")).to eq(9)
      expect(evaluate("2 ^ 3 ^ 2")).to eq(512)
      expect(evaluate("10 - 4 - 3")).to eq(3)
      expect(evaluate("-2 ^ 2")).to eq(-4)
    end

    it "識別子は与えた変数で置き換える（BMI: 65 kg・170 cm → 22.49…）" do
      expect(evaluate("body_weight / (height / 100) ^ 2", "body_weight" => 65, "height" => 170)).to be_within(1e-9).of(65 / 1.7**2)
    end
  end

  describe "round(x, n)" do
    it "小数 n 桁に丸める" do
      expect(evaluate("round(body_weight / (height / 100) ^ 2, 1)", "body_weight" => 65, "height" => 170)).to eq(22.5)
    end
  end

  describe "比較" do
    it "真偽値を返す" do
      expect(evaluate("body_mass_index < 25", "body_mass_index" => 22.5)).to be(true)
      expect(evaluate("body_mass_index >= 25", "body_mass_index" => 22.5)).to be(false)
      expect(evaluate("1 == 1.0")).to be(true)
      expect(evaluate("1 != 2")).to be(true)
      expect(evaluate("2 <= 2")).to be(true)
      expect(evaluate("3 > 2")).to be(true)
    end
  end

  describe "閉じたトークン集合（eval しない）" do
    it "未知の識別子・関数・記号は Opt::Formula::Error" do
      expect { evaluate("height * 2") }.to raise_error(Opt::Formula::Error, /height/)
      expect { evaluate("system(1)") }.to raise_error(Opt::Formula::Error)
      expect { evaluate("1; 2") }.to raise_error(Opt::Formula::Error)
      expect { evaluate("`ls`") }.to raise_error(Opt::Formula::Error)
      expect { evaluate("(1 + 2") }.to raise_error(Opt::Formula::Error)
      expect { evaluate("1 2") }.to raise_error(Opt::Formula::Error)
    end
  end
end
