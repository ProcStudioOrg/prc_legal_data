class AddAdditionalFieldsToLawyers < ActiveRecord::Migration[8.0]
  def change
    add_column :lawyers, :social_name, :string
    add_column :lawyers, :has_society, :boolean, default: false
    add_column :lawyers, :cna_link, :string
    add_column :lawyers, :detail_url, :string
    add_column :lawyers, :zip_address, :string
    add_column :lawyers, :society_basic_details, :jsonb

    add_index :lawyers, :has_society
  end
end
