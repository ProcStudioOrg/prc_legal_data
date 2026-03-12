class UpdateLawyerIndices < ActiveRecord::Migration[8.0]
  def change
    remove_index :lawyers, name: "index_lawyers_on_state_and_oab_number"
  end
end
