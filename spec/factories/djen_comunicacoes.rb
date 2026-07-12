FactoryBot.define do
  factory :djen_comunicacao do
    association :djen_monitoring
    sequence(:djen_id) { |n| 560_000_000 + n }
    djen_hash { SecureRandom.hex(15) }
    sequence(:numero_processo) { |n| "0055634252025816#{format('%04d', n)}" }
    sigla_tribunal { "TJPR" }
    data_disponibilizacao { Date.current }
    ativo { true }
    labels { ["novo_processo"] }
    raw { { "id" => djen_id, "siglaTribunal" => sigla_tribunal } }

    trait :pushed do
      pushed_at { 1.hour.ago }
    end

    trait :cancelled do
      ativo { false }
    end
  end
end
