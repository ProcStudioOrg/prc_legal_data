class AddPrincipalLawyerRefToLawyers < ActiveRecord::Migration[8.0]
  def change
    # Adiciona a coluna para referenciar o advogado principal
    # null: true porque os registros principais não terão essa referência
    # foreign_key: true cria a restrição de chave estrangeira para a própria tabela lawyers
    add_reference :lawyers, :principal_lawyer, null: true, foreign_key: { to_table: :lawyers }

    # Adiciona índices para otimizar as buscas que faremos no script e na API
    add_index :lawyers, :full_name
  end
end

