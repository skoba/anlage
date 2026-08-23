require "rails_helper"
require_relative "support/height_seed"

RSpec.describe "デモクエリ（案A: 実パイプライン駆動シード）", type: :model do
  describe "1. height不等号クエリ" do
    it "供給済みクエリが期待件数（1件）で実行できる" do
      HeightSeed.seed!(165.0)
      HeightSeed.seed!(170.0)
      HeightSeed.seed!(180.0)

      query = <<~AQL
        SELECT o/data[at0001]/events[at0002]/data[at0003]/items[at0004]/value/magnitude AS height
        FROM EHR e CONTAINS COMPOSITION c CONTAINS OBSERVATION o[openEHR-EHR-OBSERVATION.height.v2]
        WHERE o/data[at0001]/events[at0002]/data[at0003]/items[at0004]/value/magnitude > 170
      AQL

      result = OpenehrRails::Aql::Executor.execute(query)

      expect(result.rows).to eq([ [ 180.0 ] ])
    end
  end
end
