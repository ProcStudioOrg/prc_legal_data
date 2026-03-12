class CreateLawyers < ActiveRecord::Migration[8.0]
  def change
    create_table :lawyers do |t|
      t.string :full_name
      t.string :oab_number
      t.string :city
      t.string :state
      t.string :address
      t.string :zip_code
      t.string :phone_number_1
      t.string :phone_number_2
      t.string :profile_picture
      t.string :cna_picture
      t.string :situation
      t.boolean :suplementary
      t.boolean :is_procstudio
      t.boolean :has_society
      t.integer :society_id
      t.string :specialty
      t.text :bio
      t.string :email
      t.string :instagram
      t.string :website

      t.timestamps
    end

  end
end
