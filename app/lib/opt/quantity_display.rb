module Opt
  # 数量の表示の文字（skoba/anlage#250、R-20261127-20）。精度を作らない:
  # DV_QUANTITY の precision（0 以上）があればその桁で出す。無い（nil、または -1〔RM の「制限なし」〕）なら、
  # 整数の値に小数点を付けず（148.0 → 148）、小数の値はそのまま出す
  module QuantityDisplay
    module_function

    def format(magnitude, precision = nil)
      number = magnitude.is_a?(Numeric) ? magnitude : Float(magnitude.to_s)
      return Kernel.format("%.#{precision}f", number) if precision.is_a?(Integer) && precision >= 0
      return number.to_i.to_s if number.is_a?(Integer) || (number.finite? && number == number.truncate)

      number.to_s
    rescue ArgumentError, TypeError
      magnitude.to_s
    end
  end
end
