FactoryBot.define do
  factory :djen_comunicacao do
    association :djen_monitoring
    sequence(:djen_id) { |n| 560_000_000 + n }
    djen_hash { SecureRandom.hex(15) }
    sequence(:numero_processo) { |n| "0055634252025816#{format('%04d', n)}" }
    sigla_tribunal { "TJPR" }
    data_disponibilizacao { Date.current }
    ativo { true }
    labels { [ "novo_processo" ] }
    raw { { "id" => djen_id, "siglaTribunal" => sigla_tribunal } }

    # Entrega já carimbada. `to:` (e opcionalmente `and_to:`) dizem para QUAL
    # destino; o default é o destino de exemplo usado pelos specs do pusher.
    trait :pushed do
      transient do
        to { Djen::Destination.new(base_url: "https://procstudio.example.com", token: "secret-token") }
        and_to { nil }
        cancellation_pushed { false }
      end

      after(:create) do |comunicacao, evaluator|
        [ evaluator.to, evaluator.and_to ].compact.each do |destination|
          create(:djen_delivery,
                 djen_comunicacao: comunicacao,
                 destination: destination.key,
                 pushed_at: 1.hour.ago,
                 cancellation_pushed_at: evaluator.cancellation_pushed ? 1.minute.ago : nil)
        end
      end
    end

    trait :cancellation_pushed do
      transient { cancellation_pushed { true } }
    end

    trait :cancelled do
      ativo { false }
    end
  end
end
