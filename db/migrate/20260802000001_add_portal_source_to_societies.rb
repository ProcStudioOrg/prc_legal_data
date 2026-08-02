class AddPortalSourceToSocieties < ActiveRecord::Migration[8.1]
  # Sociedades vindas do portal da OAB-MG não têm inscrição OAB: a aba
  # "Sociedade de Advogados" expõe apenas nome, endereço, CEP, telefone,
  # e-mail e site (ver prc_scrapper_oab/oab-mg/parser.rb#societies).
  #
  # A chave passa a ser o `oab_id` no formato MG_<ordem>_SOCIEDADE, derivado do
  # advogado que revelou a sociedade. `oab_id` é sujo no legado (166k linhas,
  # 140k distintas, valores como "374" e "00206/705"), então a unicidade entra
  # como índice PARCIAL, só sobre as linhas de origem portal.
  def change
    add_column :societies, :email,   :string, if_not_exists: true
    add_column :societies, :website, :string, if_not_exists: true

    # cna | oab_portal | cnpja — de onde a linha veio.
    add_column :societies, :source, :string, if_not_exists: true

    # Enriquecimento CNPJA (PLANO-CNPJA.md §6).
    add_column :societies, :cnpj,                   :string,   if_not_exists: true
    add_column :societies, :cnpja_data,             :jsonb,    default: {}, null: false, if_not_exists: true
    add_column :societies, :cnpja_updated_at,       :datetime, if_not_exists: true
    add_column :societies, :cnpja_synced_at,        :datetime, if_not_exists: true
    add_column :societies, :cnpja_match_confidence, :string,   if_not_exists: true

    add_column :lawyers, :cnpja_person_id, :string, if_not_exists: true

    add_index :societies, :source, if_not_exists: true
    add_index :societies, :cnpj, unique: true, where: 'cnpj IS NOT NULL', if_not_exists: true
    add_index :societies, :oab_id,
              unique: true,
              where: "source = 'oab_portal'",
              name: 'index_societies_on_oab_id_portal',
              if_not_exists: true

    # O import casa sociedade por nome normalizado dentro da UF; sem isso a
    # varredura de 4.095 nomes vira seq scan em 166k linhas.
    add_index :societies, %i[state name], if_not_exists: true

    # Backfill: tudo que existe hoje veio do scrape do CNA.
    reversible do |dir|
      dir.up { execute "UPDATE societies SET source = 'cna' WHERE source IS NULL" }
    end
  end
end
