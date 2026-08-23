class AddUidToCompositions < ActiveRecord::Migration[8.1]
  def change
    add_column :compositions, :uid, :string
  end
end
