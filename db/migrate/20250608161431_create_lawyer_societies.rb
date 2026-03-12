class CreateLawyerSocieties < ActiveRecord::Migration[8.0]
  def change
    create_table :lawyer_societies do |t|
      t.references :lawyer, null: false, foreign_key: true
      t.references :society, null: false, foreign_key: true
      t.string :partnership_type

      t.timestamps
    end
  end
end
