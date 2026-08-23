module Opt
  class PathcardExtractor
    Result = Struct.new(:cards, :report, keyword_init: true)

    def self.call(template)
      new(template).call
    end

    def initialize(template)
      @template = template
    end

    def call
      Result.new(cards: [empty_card], report: {})
    end

    private

    # Placeholder shape for TODO 1 ([shape]) -- real node walking and
    # field population land in the later TODOs (wp2-plan.md 5節).
    def empty_card
      {
        "schema_version" => "1.0",
        "identity" => {},
        "semantics" => {},
        "constraints" => {},
        "bindings" => [],
        "capture" => {},
        "reserved" => {},
        "provenance" => {}
      }
    end
  end
end
