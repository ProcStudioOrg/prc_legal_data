class RemoveHasSocietyAndSocietyIdFromLawyers < ActiveRecord::Migration[8.0]
  def change
    remove_column :lawyers, :has_society, :string
    remove_column :lawyers, :society_id, :integer
  end
end
