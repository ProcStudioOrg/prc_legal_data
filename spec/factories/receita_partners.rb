FactoryBot.define do
  factory :receita_partner do
    receita_company
    sequence(:nome_socio) { |n| "SOCIO NUMERO #{n}" }
    name_normalized { Receita::NameNormalizer.call(nome_socio) }
    sequence(:documento) { |n| format('***%06d**', n) }
    identificador { ReceitaPartner::PESSOA_FISICA }
    qualificacao { 'Sócio-Administrador' }
    data_entrada_sociedade { Date.new(2019, 3, 4) }
    faixa_etaria { '31 a 40 anos' }
    first_seen_release { '2026-08' }
    last_seen_release { '2026-08' }
  end
end
