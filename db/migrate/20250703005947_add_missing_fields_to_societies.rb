class AddMissingFieldsToSocieties < ActiveRecord::Migration[8.0]
  def change
    add_column :societies, :situacao, :string
    add_column :societies, :phone_number_2, :string
  end
end
