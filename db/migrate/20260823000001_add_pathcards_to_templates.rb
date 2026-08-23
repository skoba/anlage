class AddPathcardsToTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :templates, :pathcards, :json
  end
end
