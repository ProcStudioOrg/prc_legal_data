class AddCnaLinkToLawyerSocieties < ActiveRecord::Migration[8.0]
  def change
    add_column :lawyer_societies, :cna_link, :string
  end
end
