class AddCrmDataToSocieties < ActiveRecord::Migration[8.1]
  # Espelha `crm_data` de lawyers (20260117025441). Campo SEPARADO de
  # `cnpja_data`: aquele é payload cru da Receita, sobrescrito a cada sync do
  # EnrichSocietyJob; este é estado de prospecção nosso e não pode ser perdido
  # quando o CNPJA reescreve o dado externo.
  def change
    add_column :societies, :crm_data, :jsonb, default: {}, null: false
    add_index :societies, :crm_data, using: :gin
  end
end
