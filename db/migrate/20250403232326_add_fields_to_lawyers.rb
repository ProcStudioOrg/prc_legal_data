class AddFieldsToLawyers < ActiveRecord::Migration[8.0]
  def change
    # If oab_id doesn't exist yet
    add_column :lawyers, :oab_id, :string unless column_exists?(:lawyers, :oab_id)
    
    # Add other new fields that weren't in your original schema
    add_column :lawyers, :situation, :string unless column_exists?(:lawyers, :situation)
    add_column :lawyers, :suplementary, :boolean unless column_exists?(:lawyers, :suplementary)
    add_column :lawyers, :is_procstudio, :boolean unless column_exists?(:lawyers, :is_procstudio)
    add_column :lawyers, :has_society, :boolean unless column_exists?(:lawyers, :has_society)
    add_column :lawyers, :society_id, :string unless column_exists?(:lawyers, :society_id)
    add_column :lawyers, :cna_picture, :string unless column_exists?(:lawyers, :cna_picture)
    
    # Add indexes for fields you'll search by frequently
    add_index :lawyers, :oab_id, unique: true unless index_exists?(:lawyers, :oab_id)
  end
end