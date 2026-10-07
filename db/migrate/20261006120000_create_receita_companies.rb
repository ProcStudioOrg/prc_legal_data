# frozen_string_literal: true

# Recorte de advocacia (CNAE 6911701) do dump mensal do OpenCNPJ, mais linhas
# avulsas vindas da API pública (source = 'opencnpj_api'). Ver a spec em
# docs/superpowers/specs/2026-10-06-receita-cnpj-enrichment-design.md §5.1.
#
# `receita_partners` nunca apaga sócio que saiu: `last_seen_release` fica na
# release antiga e isso é o diff de quadro societário.
class CreateReceitaCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :receita_companies do |t|
      t.string :cnpj, null: false, limit: 14
      t.string :cnpj_root, null: false, limit: 8
      t.string :razao_social
      t.string :nome_fantasia
      t.string :name_normalized
      t.string :situacao_cadastral
      t.date :data_situacao_cadastral
      t.string :motivo_situacao
      t.boolean :matriz, null: false, default: true
      t.date :data_inicio_atividade
      t.string :cnae_principal
      t.string :natureza_juridica
      t.string :tipo_logradouro
      t.string :logradouro
      t.string :numero
      t.string :complemento
      t.string :bairro
      t.string :cep
      t.string :uf
      t.string :municipio
      t.string :codigo_municipio
      t.string :email
      t.jsonb :telefones, null: false, default: []
      t.decimal :capital_social, precision: 15, scale: 2
      t.string :porte_empresa
      t.string :opcao_simples
      t.date :data_opcao_simples
      t.string :opcao_mei
      t.jsonb :raw, null: false, default: {}
      t.string :source, null: false, default: 'dump'
      t.string :release
      t.datetime :fetched_at, null: false
      t.references :society, foreign_key: true
      t.string :match_confidence
      t.datetime :matched_at

      t.timestamps
    end

    add_index :receita_companies, :cnpj, unique: true
    add_index :receita_companies, :cnpj_root
    add_index :receita_companies, [:uf, :name_normalized]
    add_index :receita_companies, :data_inicio_atividade
    add_index :receita_companies, :natureza_juridica
    add_index :receita_companies, :updated_at

    create_table :receita_partners do |t|
      t.references :receita_company, null: false, foreign_key: true, index: false
      t.string :nome_socio
      t.string :name_normalized
      t.string :documento
      t.string :identificador
      t.string :qualificacao
      t.date :data_entrada_sociedade
      t.string :faixa_etaria
      t.references :lawyer, foreign_key: true
      t.string :first_seen_release
      t.string :last_seen_release

      t.timestamps
    end

    add_index :receita_partners, [:receita_company_id, :name_normalized, :documento],
              unique: true, name: 'index_receita_partners_unique_member'
    add_index :receita_partners, :name_normalized
  end
end
