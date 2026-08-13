class CreateCompositions < ActiveRecord::Migration[8.1]
  def change
    create_table :compositions do |t|
      t.references :template, null: false, foreign_key: true
      t.json :rm_composition, null: false

      t.timestamps
    end
  end
end
