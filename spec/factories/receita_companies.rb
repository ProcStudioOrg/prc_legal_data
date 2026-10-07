FactoryBot.define do
  factory :receita_company do
    sequence(:cnpj) { |n| format('%014d', 10_000_000_000_100 + n * 100) }
    cnpj_root { cnpj[0, 8] }
    sequence(:razao_social) { |n| "FIRMA #{n} ADVOGADOS ASSOCIADOS" }
    name_normalized { Receita::NameNormalizer.call(razao_social) }
    situacao_cadastral { 'Ativa' }
    matriz { true }
    data_inicio_atividade { Date.new(2019, 3, 4) }
    cnae_principal { '6911701' }
    natureza_juridica { 'Sociedade Simples Pura' }
    tipo_logradouro { 'RUA' }
    logradouro { 'PARANA' }
    numero { '3056' }
    bairro { 'CENTRO' }
    cep { '85810010' }
    uf { 'PR' }
    municipio { 'CASCAVEL' }
    email { 'contato@firma.adv.br' }
    telefones { [{ 'ddd' => '45', 'numero' => '30355898', 'is_fax' => false }] }
    capital_social { 10_000 }
    porte_empresa { 'Micro Empresa (ME)' }
    opcao_simples { 'S' }
    raw { { 'cnpj' => cnpj } }
    source { ReceitaCompany::SOURCE_DUMP }
    release { '2026-08' }
    fetched_at { Time.current }

    trait :from_api do
      source { ReceitaCompany::SOURCE_API }
      release { nil }
    end

    trait :negative_cache do
      from_api
      raw { {} }
      razao_social { nil }
      name_normalized { nil }
      situacao_cadastral { nil }
    end
  end
end
