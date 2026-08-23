# 暫定・実パイプライン非経由（Plan B, docs/design/demo-queries-plan.md 2節）。
#
# ここでのシードは Opt::CompositionBuilder / TemplatesController のドロップゾーン
# 経路を一切通らない。OpenehrRails::Rm::CompositionCommitter を直接呼び、
# openEHR-EHR-OBSERVATION.height.v2 の実archetype構造（openehr-rails gem側の
# 実fixture spec/generators/templates/bmi_calculation.opt で検証済み。
# docs/reports/demo-queries-log.md R2参照）を手作業で構成した canonical hash を
# 投入する足場（scaffold）である。
#
# height.v2 の実OPT fixture（CKM/Archetype Designer経由、人間依頼中）が届き次第、
# このファイルとシードは案A（実OPT駆動）へ差し替える。11/5凍結の受入条件
# 「デモクエリ spec green」に数えられるのは案A差し替え後のみで、この暫定specは
# 数えられない（docs/design/demo-queries-plan.md 7節-1裁定）。

require "rails_helper"
require_relative "support/height_seed_provisional"

RSpec.describe "デモクエリ（暫定・実パイプライン非経由のPlan Bシード）", type: :model do
  describe "1. height不等号クエリ" do
    it "供給済みクエリが期待件数（1件）で実行できる" do
      HeightSeedProvisional.seed!([ 165.0, 170.0, 180.0 ])

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
