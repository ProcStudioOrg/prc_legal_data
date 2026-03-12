class AddFieldsToSocieties < ActiveRecord::Migration[8.0]
  def change
    add_column :societies, :name, :string
    add_column :societies, :society_link, :string
    add_column :societies, :number_of_partners, :integer
    add_column :societies, :idt, :integer
  end
end
