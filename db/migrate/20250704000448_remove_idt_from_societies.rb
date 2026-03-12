class RemoveIdtFromSocieties < ActiveRecord::Migration[8.0]
  def change
    remove_column :societies, :idt, :integer
  end
end
