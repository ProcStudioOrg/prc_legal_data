class AddCrmDataToLawyers < ActiveRecord::Migration[8.1]
  def change
    add_column :lawyers, :crm_data, :jsonb, default: {}, null: false
    add_index :lawyers, :crm_data, using: :gin
  end
end
