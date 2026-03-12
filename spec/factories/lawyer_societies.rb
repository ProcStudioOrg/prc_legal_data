FactoryBot.define do
  factory :lawyer_society do
    association :lawyer
    association :society
    partnership_type { :socio }

    trait :associado do
      partnership_type { :associado }
    end

    trait :socio_de_servico do
      partnership_type { :socio_de_servico }
    end
  end
end
