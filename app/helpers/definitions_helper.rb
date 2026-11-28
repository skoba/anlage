module DefinitionsHelper
  # 遷移の図をサーバで SVG に描く（docs/design/definition-layer-plan.md 3.1、skoba/anlage#260。依存なし。U1 のグラフと同じ作り）。
  # 段（layer）を左から右へ、同じ段の節を上から下へ。辺は節の右端から左端への線（戻る辺は、同じ線で向きが逆になる）
  DIAGRAM_NODE = { width: 160, height: 40, gap_x: 70, gap_y: 30, pad: 16 }.freeze

  # 定義の組の画面（skoba/anlage#296）の文言。正典は docs/demo/ui-vocabulary.md の「定義の組」
  BUNDLE_STATUS_LABELS = { "draft" => "下書き", "active" => "動いている", "superseded" => "前の版" }.freeze

  def bundle_status_label(status) = BUNDLE_STATUS_LABELS.fetch(status, status)

  # 検査の結果（Definitions::Linter::Report）の一言。案は D8（出どころとレビュー者の無いロジック）
  def lint_summary(report)
    return "通らない（エラー #{report.errors.size} 件）" unless report.ok?

    "通る（案 #{report.problems.count { _1.severity == :draft }} 件）"
  end

  def transition_diagram(diagram)
    positions = diagram_positions(diagram.nodes)
    width = positions.values.map { _1[:x] }.max.to_i + DIAGRAM_NODE[:width] + DIAGRAM_NODE[:pad]
    height = positions.values.map { _1[:y] }.max.to_i + DIAGRAM_NODE[:height] + DIAGRAM_NODE[:pad]

    content_tag(:svg, class: "transition-diagram", viewBox: "0 0 #{width} #{height}", role: "img",
                      "aria-label": "遷移の図（節 #{diagram.nodes.size}、辺 #{diagram.edges.size}）") do
      safe_join([
        content_tag(:defs, content_tag(:marker, content_tag(:path, nil, d: "M0,0 L8,4 L0,8 z"),
                                       id: "diagram-arrow", markerWidth: 8, markerHeight: 8, refX: 8, refY: 4, orient: "auto")),
        safe_join(diagram.edges.map { diagram_edge(_1, positions) }),
        safe_join(diagram.nodes.map { diagram_node(_1, positions.fetch(_1.id)) })
      ])
    end
  end

  private

  def diagram_positions(nodes)
    nodes.group_by(&:layer).flat_map do |layer, members|
      members.each_with_index.map do |node, index|
        [ node.id, { x: DIAGRAM_NODE[:pad] + layer * (DIAGRAM_NODE[:width] + DIAGRAM_NODE[:gap_x]),
                     y: DIAGRAM_NODE[:pad] + index * (DIAGRAM_NODE[:height] + DIAGRAM_NODE[:gap_y]) } ]
      end
    end.to_h
  end

  def diagram_node(node, position)
    content_tag(:g, class: "diagram-node diagram-#{node.kind}", "data-node": node.id) do
      safe_join([
        content_tag(:rect, nil, x: position[:x], y: position[:y], width: DIAGRAM_NODE[:width], height: DIAGRAM_NODE[:height], rx: 6),
        content_tag(:text, node.label, x: position[:x] + DIAGRAM_NODE[:width] / 2, y: position[:y] + DIAGRAM_NODE[:height] / 2 + 5,
                                       "text-anchor": "middle")
      ])
    end
  end

  def diagram_edge(edge, positions)
    from = positions.fetch(edge.from)
    to = positions.fetch(edge.to)
    forward = to[:x] > from[:x]
    x1 = forward ? from[:x] + DIAGRAM_NODE[:width] : from[:x]
    x2 = forward ? to[:x] : to[:x] + DIAGRAM_NODE[:width]
    y1 = from[:y] + DIAGRAM_NODE[:height] / 2 + (forward ? 0 : 8)
    y2 = to[:y] + DIAGRAM_NODE[:height] / 2 + (forward ? 0 : 8)
    content_tag(:g, class: "diagram-edge#{' diagram-back' unless forward}", "data-from": edge.from, "data-to": edge.to) do
      safe_join([
        content_tag(:line, nil, x1:, y1:, x2:, y2:, "marker-end": "url(#diagram-arrow)"),
        content_tag(:text, edge.label, x: (x1 + x2) / 2, y: [ y1, y2 ].min - 4, "text-anchor": "middle", class: "diagram-label")
      ])
    end
  end
end
