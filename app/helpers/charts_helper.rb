module ChartsHelper
  # 患者の画面の時系列の折れ線を、サーバで SVG に描く（skoba/anlage#220、docs/design/u1-patient-chart-plan.md 3.3。依存なし）。
  # 横軸は時刻、縦軸は値。点が 2 つ未満なら描かない（nil）。値の表は、この図の下に別に出す
  CHART_WIDTH = 560
  CHART_HEIGHT = 160
  CHART_PAD = { left: 48, right: 16, top: 12, bottom: 28 }.freeze

  def series_chart(points, units:, label:)
    return nil if points.size < 2

    times = points.map { _1.at.to_f }
    values = points.map(&:value)
    x = scale(times, CHART_PAD[:left], CHART_WIDTH - CHART_PAD[:right])
    y = scale(values, CHART_HEIGHT - CHART_PAD[:bottom], CHART_PAD[:top])
    coords = points.map { [ x.call(_1.at.to_f).round(1), y.call(_1.value).round(1) ] }

    content_tag(:svg, class: "series-chart", viewBox: "0 0 #{CHART_WIDTH} #{CHART_HEIGHT}", role: "img",
                      "aria-label": "#{label}（#{units}）の推移", "data-points": points.size) do
      safe_join([
        axis_lines,
        content_tag(:polyline, nil, points: coords.map { _1.join(",") }.join(" "), class: "series-line"),
        safe_join(coords.map { |cx, cy| content_tag(:circle, nil, cx:, cy:, r: 3, class: "series-point") }),
        axis_label(values.max, CHART_PAD[:left] - 6, CHART_PAD[:top] + 4, "end"),
        axis_label(values.min, CHART_PAD[:left] - 6, CHART_HEIGHT - CHART_PAD[:bottom], "end"),
        axis_label(recorded_date(points.first.at), CHART_PAD[:left], CHART_HEIGHT - 8, "start"),
        axis_label(recorded_date(points.last.at), CHART_WIDTH - CHART_PAD[:right], CHART_HEIGHT - 8, "end")
      ])
    end
  end

  private

  # 値の範囲を画面の座標へ。範囲が 0 なら真ん中
  def scale(range_values, from, to)
    min, max = range_values.minmax
    return ->(_) { (from + to) / 2.0 } if min == max

    ->(value) { from + (value - min) * (to - from) / (max - min) }
  end

  def axis_lines
    bottom = CHART_HEIGHT - CHART_PAD[:bottom]
    safe_join([
      content_tag(:line, nil, x1: CHART_PAD[:left], y1: CHART_PAD[:top], x2: CHART_PAD[:left], y2: bottom, class: "series-axis"),
      content_tag(:line, nil, x1: CHART_PAD[:left], y1: bottom, x2: CHART_WIDTH - CHART_PAD[:right], y2: bottom, class: "series-axis")
    ])
  end

  def axis_label(text, x, y, anchor)
    content_tag(:text, text, x:, y:, "text-anchor": anchor, class: "series-label")
  end
end
