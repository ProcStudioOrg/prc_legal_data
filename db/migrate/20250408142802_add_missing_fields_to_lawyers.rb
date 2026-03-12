class AddMissingFieldsToLawyers < ActiveRecord::Migration[8.0]
  def change
    add_column :lawyers, :profession, :string
    add_column :lawyers, :folder_id, :string
  end
end