# 暫定・実パイプライン非経由（Plan B、docs/design/demo-queries-plan.md 2節）。
# Opt::CompositionBuilderもTemplatesControllerのドロップゾーンも通らない。
# openEHR-EHR-OBSERVATION.height.v2 の実archetype構造（openehr-rails gem側の実fixture
# spec/generators/templates/bmi_calculation.opt で検証済み。archetype_id/at-code/RM型は
# 実物、magnitude値のみデモ用の作成値）を手作業のcanonical hashで組み立て、
# OpenehrRails::Rm::CompositionCommitter.commit へ直接投入する。
#
# height.v2の実OPT fixture到着後、この足場ごと削除し案A（実OPT駆動）へ差し替える。
module HeightSeedProvisional
  module_function

  def seed!(magnitudes_cm)
    magnitudes_cm.each { |magnitude| seed_one!(magnitude) }
  end

  def seed_one!(magnitude_cm)
    now = Time.current.iso8601

    hash = {
      "_type" => "COMPOSITION",
      "archetype_node_id" => "openEHR-EHR-COMPOSITION.report-result.v1",
      "name" => { "value" => "Demo height measurement (provisional)" },
      "archetype_details" => {
        "archetype_id" => { "value" => "openEHR-EHR-COMPOSITION.report-result.v1" },
        "template_id" => { "value" => "demo-height-provisional" }
      },
      "content" => [
        {
          "_type" => "OBSERVATION",
          "archetype_node_id" => "openEHR-EHR-OBSERVATION.height.v2",
          "archetype_details" => { "archetype_id" => { "value" => "openEHR-EHR-OBSERVATION.height.v2" } },
          "name" => { "value" => "Height/Length" },
          "data" => {
            "_type" => "HISTORY",
            "archetype_node_id" => "at0001",
            "origin" => { "value" => now },
            "events" => [
              {
                "_type" => "POINT_EVENT",
                "archetype_node_id" => "at0002",
                "time" => { "value" => now },
                "data" => {
                  "_type" => "ITEM_TREE",
                  "archetype_node_id" => "at0003",
                  "items" => [
                    {
                      "_type" => "ELEMENT",
                      "archetype_node_id" => "at0004",
                      "name" => { "value" => "Height/Length" },
                      "value" => { "_type" => "DV_QUANTITY", "magnitude" => magnitude_cm, "units" => "cm" }
                    }
                  ]
                }
              }
            ]
          }
        }
      ]
    }

    OpenehrRails::Rm::CompositionCommitter.commit(hash, uid: SecureRandom.uuid, owner: nil)
  end
end
