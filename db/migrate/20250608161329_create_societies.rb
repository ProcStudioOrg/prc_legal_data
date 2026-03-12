class CreateSocieties < ActiveRecord::Migration[8.0]
  def change
    create_table :societies do |t|
      t.integer :inscricao
      t.string :state
      t.string :oab_id
      t.string :address
      t.string :zip_code
      t.string :city
      t.string :phone

      t.timestamps
    end
  end
end
