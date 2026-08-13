class CreateTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :templates do |t|
      t.string :template_id, null: false
      t.string :version, null: false, default: "1.0.0"
      t.text :source_xml, null: false
      t.json :web_template
      t.string :status, null: false, default: "active"
      t.string :checksum, null: false
      t.datetime :dropped_at
      t.string :dropped_by

      t.timestamps
    end
    add_index :templates, [ :template_id, :version ], unique: true
    add_index :templates, :checksum, unique: true
  end
end
