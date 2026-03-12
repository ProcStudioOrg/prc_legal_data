FactoryBot.define do
  factory :lawyer do
    sequence(:full_name) { |n| "Advogado Teste #{n}" }
    sequence(:oab_number) { |n| (100000 + n).to_s }
    state { "SP" }
    sequence(:oab_id) { |n| "SP_#{100000 + n}" }
    city { "São Paulo" }
    address { "Rua Teste, 123" }
    zip_code { "01234-567" }
    phone_number_1 { "(11) 99999-9999" }
    situation { "situação regular" }
    profession { "ADVOGADO" }
    suplementary { false }
    is_procstudio { false }
    has_society { false }

    trait :with_society do
      after(:create) do |lawyer|
        society = create(:society)
        create(:lawyer_society, lawyer: lawyer, society: society)
      end
    end

    trait :supplementary do
      suplementary { true }
      association :principal_lawyer, factory: :lawyer
    end
  end
end
