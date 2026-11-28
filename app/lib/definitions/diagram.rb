module Definitions
  # 遷移の図（docs/design/definition-layer-plan.md 3.1、skoba/anlage#260）。画面が節、ボタンの open.screen が辺、
  # open.form は帳票の節への辺、then は帳票の節から先（画面か「保存した記録」）への辺。
  # 配置は単純: start から辿った段（layer）を左から右へ。検査でエラーのある組からは作らない
  class Diagram
    Node = Data.define(:id, :kind, :label, :layer)
    Edge = Data.define(:from, :to, :label)
    SAVED = "record:saved".freeze

    attr_reader :nodes, :edges

    def self.from(report)
      raise ArgumentError, "検査でエラーのある組からは図を作らない（#{report.errors.size} 件）" unless report.ok? && report.bundle

      new(report.bundle, report.screens)
    end

    def initialize(bundle, screens)
      @titles = screens.to_h { [ _1.id, _1.data["title"] || _1.id ] }
      @labels = {}
      start = node_id(:screen, bundle.data.dig("start", "screen"))
      @edges = screens.flat_map { screen_edges(_1) }.uniq
      @nodes = layered(start)
    end

    def to_mermaid
      lines = [ "flowchart LR" ]
      nodes.each { |node| lines << "  #{key(node.id)}#{shape(node)}" }
      edges.each { |edge| lines << "  #{key(edge.from)} -->|#{edge.label.to_json}| #{key(edge.to)}" }
      lines.join("\n") + "\n"
    end

    private

    def screen_edges(screen)
      from = node_id(:screen, screen.id)
      screen.data["sections"].flat_map { Array(_1["items"]) }.flat_map do |button|
        open = button["open"]
        target = open["form"] ? node_id(:form, open["form"]) : node_id(:screen, open["screen"])
        then_edge = open["form"] && open["then"] && Edge.new(from: target, to: then_target(open["then"]), label: "保存のあと")
        [ Edge.new(from:, to: target, label: button["label"]), then_edge ].compact
      end
    end

    def then_target(then_spec) = then_spec["screen"] ? node_id(:screen, then_spec["screen"]) : node_id(:record, "saved")

    def node_id(kind, name)
      id = "#{kind}:#{name}"
      @labels[id] ||= { screen: -> { @titles[name] || name }, form: -> { "帳票 #{name}" }, record: -> { "保存した記録" } }.fetch(kind).call
      id
    end

    # start から辺を辿り、最初に着いた段の順に並べる。たどり着けない節（D6 で落ちるので、ふつうは無い）は最後の段
    def layered(start)
      layers = { start => 0 }
      queue = [ start ]
      while (current = queue.shift)
        edges.select { _1.from == current }.each do |edge|
          next if layers.key?(edge.to)

          layers[edge.to] = layers[current] + 1
          queue << edge.to
        end
      end
      ids = ([ start ] + edges.flat_map { [ _1.from, _1.to ] }).uniq
      last = (layers.values.max || 0) + 1
      ids.map { |id| Node.new(id:, kind: id.split(":").first.to_sym, label: @labels.fetch(id), layer: layers.fetch(id, last)) }
         .sort_by.with_index { |node, index| [ node.layer, index ] }
    end

    def key(id) = id.tr(":", "_").gsub(/[^A-Za-z0-9_]/, "_")

    def shape(node)
      label = node.label.to_json
      case node.kind
      when :form then "[/#{label}/]"
      when :record then "([#{label}])"
      else "[#{label}]"
      end
    end
  end
end
