FactoryBot.define do
  factory :society do
    sequence(:inscricao) { |n| 100000 + n }
    sequence(:name) { |n| "Sociedade de Advogados #{n}" }
    state { "SP" }
    sequence(:oab_id) { |n| "SP_SOC_#{100000 + n}" }
    address { "Rua Exemplo, 123" }
    zip_code { "01234-567" }
    city { "São Paulo" }
    phone { "(11) 99999-9999" }
    number_of_partners { 3 }
    situacao { "Ativo" }

    trait :with_lawyer do
      after(:create) do |society|
        lawyer = create(:lawyer)
        create(:lawyer_society, society: society, lawyer: lawyer)
      end
    end

    trait :with_lawyers do
      transient do
        lawyers_count { 2 }
      end

      after(:create) do |society, evaluator|
        evaluator.lawyers_count.times do
          lawyer = create(:lawyer)
          create(:lawyer_society, society: society, lawyer: lawyer)
        end
      end
    end
  end
end
