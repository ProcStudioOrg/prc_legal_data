class AddDjenAdvogadoIdToLawyers < ActiveRecord::Migration[8.1]
  def change
    add_column :lawyers, :djen_advogado_id, :bigint
    add_index :lawyers, :djen_advogado_id
  end
end
