# 定義の組の登録（docs/design/definition-registration-plan.md 1 節、skoba/anlage#277、R-20261128-7）。
# 1 行 = 1 つの組の 1 つの版。files は path → YAML の文字（読み直すたびに Definitions::Loader で読む）
class CreateDefinitionBundles < ActiveRecord::Migration[8.1]
  def change
    create_table :definition_bundles do |t|
      t.string :bundle_id, null: false
      t.string :version, null: false
      t.string :status, null: false, default: "draft"
      t.json :files, null: false
      t.string :checksum, null: false
      t.json :lint_report
      t.string :restored_from
      t.string :registered_by
      t.timestamps
    end
    add_index :definition_bundles, %i[bundle_id version], unique: true
    # active は組ごとに 1 つ
    add_index :definition_bundles, :bundle_id, unique: true, where: "status = 'active'", name: "index_definition_bundles_one_active"
  end
end
