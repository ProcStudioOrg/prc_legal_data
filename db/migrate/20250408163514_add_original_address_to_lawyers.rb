class AddOriginalAddressToLawyers < ActiveRecord::Migration[8.0]
  def change
    add_column :lawyers, :original_address, :text
  end
end