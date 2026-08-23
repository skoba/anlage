# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_23_000001) do
  create_table "compositions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "rm_composition", null: false
    t.integer "template_id", null: false
    t.datetime "updated_at", null: false
    t.index [ "template_id" ], name: "index_compositions_on_template_id"
  end

  create_table "openehr_ehrs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ehr_id", null: false
    t.boolean "is_modifiable", default: true, null: false
    t.boolean "is_queryable", default: true, null: false
    t.json "other_details"
    t.string "subject_id"
    t.string "subject_namespace"
    t.string "system_id"
    t.datetime "time_created", null: false
    t.datetime "updated_at", null: false
    t.index [ "ehr_id" ], name: "index_openehr_ehrs_on_ehr_id", unique: true
  end

  create_table "openehr_rm_compositions", force: :cascade do |t|
    t.string "archetype_node_id", null: false
    t.string "category_code"
    t.string "category_value"
    t.string "composer_name"
    t.datetime "context_start_time"
    t.datetime "created_at", null: false
    t.integer "ehr_id"
    t.json "extra"
    t.string "language_code"
    t.string "language_terminology"
    t.boolean "latest_version", default: true, null: false
    t.string "name_value"
    t.bigint "owner_id"
    t.string "owner_type"
    t.string "rm_version", default: "1.0.4", null: false
    t.string "setting_code"
    t.string "setting_value"
    t.string "template_id"
    t.string "territory_code"
    t.string "territory_terminology"
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index [ "archetype_node_id", "latest_version" ], name: "idx_on_archetype_node_id_latest_version_bd92eb1cac"
    t.index [ "ehr_id" ], name: "index_openehr_rm_compositions_on_ehr_id"
    t.index [ "owner_type", "owner_id" ], name: "index_openehr_rm_compositions_on_owner_type_and_owner_id"
    t.index [ "template_id" ], name: "index_openehr_rm_compositions_on_template_id"
    t.index [ "uid" ], name: "index_openehr_rm_compositions_on_uid"
  end

  create_table "openehr_rm_contributions", force: :cascade do |t|
    t.string "change_type_code", null: false
    t.string "change_type_value", null: false
    t.string "committer_name"
    t.datetime "created_at", null: false
    t.string "description"
    t.integer "ehr_id"
    t.string "system_id"
    t.datetime "time_committed", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index [ "ehr_id" ], name: "index_openehr_rm_contributions_on_ehr_id"
  end

  create_table "openehr_rm_data_values", force: :cascade do |t|
    t.boolean "boolean_value"
    t.string "code_string"
    t.integer "composition_id", null: false
    t.date "date_value"
    t.datetime "datetime_value"
    t.float "denominator"
    t.string "duration_value"
    t.json "extra"
    t.string "formalism"
    t.string "identifier_assigner"
    t.string "identifier_id"
    t.string "identifier_issuer"
    t.string "identifier_type"
    t.integer "integer_value"
    t.float "magnitude"
    t.string "media_type"
    t.integer "node_id", null: false
    t.float "numerator"
    t.string "path", null: false
    t.integer "precision"
    t.integer "proportion_type"
    t.string "rm_attribute_name", default: "value", null: false
    t.string "rm_type", null: false
    t.string "terminology_id"
    t.string "text_value"
    t.time "time_value"
    t.string "units"
    t.string "uri_value"
    t.index [ "composition_id" ], name: "index_openehr_rm_data_values_on_composition_id"
    t.index [ "node_id" ], name: "index_openehr_rm_data_values_on_node_id"
    t.index [ "path", "code_string" ], name: "index_openehr_rm_data_values_on_path_and_code_string"
    t.index [ "path", "magnitude" ], name: "index_openehr_rm_data_values_on_path_and_magnitude"
    t.index [ "path" ], name: "index_openehr_rm_data_values_on_path"
  end

  create_table "openehr_rm_nodes", force: :cascade do |t|
    t.string "archetype_id"
    t.string "archetype_node_id"
    t.integer "composition_id", null: false
    t.datetime "event_time"
    t.json "extra"
    t.datetime "history_origin"
    t.string "math_function_code"
    t.string "name_value"
    t.string "null_flavor_code"
    t.bigint "parent_id"
    t.string "path", null: false
    t.integer "position", default: 0, null: false
    t.string "rm_attribute_name", null: false
    t.string "rm_type", null: false
    t.string "width"
    t.index [ "archetype_node_id" ], name: "index_openehr_rm_nodes_on_archetype_node_id"
    t.index [ "composition_id", "path" ], name: "index_openehr_rm_nodes_on_composition_id_and_path"
    t.index [ "composition_id" ], name: "index_openehr_rm_nodes_on_composition_id"
    t.index [ "parent_id" ], name: "index_openehr_rm_nodes_on_parent_id"
  end

  create_table "openehr_rm_versions", force: :cascade do |t|
    t.integer "composition_id", null: false
    t.integer "contribution_id"
    t.datetime "created_at", null: false
    t.string "lifecycle_state_code", default: "532", null: false
    t.string "system_id"
    t.datetime "updated_at", null: false
    t.string "version_tree_id", null: false
    t.string "versioned_object_uid", null: false
    t.index [ "composition_id" ], name: "index_openehr_rm_versions_on_composition_id"
    t.index [ "contribution_id" ], name: "index_openehr_rm_versions_on_contribution_id"
    t.index [ "versioned_object_uid", "version_tree_id" ], name: "idx_on_versioned_object_uid_version_tree_id_d798803155", unique: true
  end

  create_table "openehr_templates", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "name"
    t.string "template_id", null: false
    t.string "template_type", default: "operational_template", null: false
    t.datetime "updated_at", null: false
    t.string "version"
    t.index [ "template_id" ], name: "index_openehr_templates_on_template_id", unique: true
  end

  create_table "templates", force: :cascade do |t|
    t.string "checksum", null: false
    t.datetime "created_at", null: false
    t.datetime "dropped_at"
    t.string "dropped_by"
    t.json "pathcards"
    t.text "source_xml", null: false
    t.string "status", default: "active", null: false
    t.string "template_id", null: false
    t.datetime "updated_at", null: false
    t.string "version", default: "1.0.0", null: false
    t.json "web_template"
    t.index [ "checksum" ], name: "index_templates_on_checksum", unique: true
    t.index [ "template_id", "version" ], name: "index_templates_on_template_id_and_version", unique: true
  end

  add_foreign_key "compositions", "templates"
end
