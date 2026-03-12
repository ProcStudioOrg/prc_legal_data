class ChangeHasSocietyToString < ActiveRecord::Migration[8.0]
  def up
    change_column :lawyers, :has_society, :string
  end

  def down
    change_column :lawyers, :has_society, :boolean
  end
end