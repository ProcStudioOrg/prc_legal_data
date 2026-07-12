FactoryBot.define do
  factory :djen_monitoring do
    association :lawyer
    active { true }
    source { "procstudio" }

    trait :inactive do
      active { false }
    end

    trait :onboarded do
      onboarded_at { 1.day.ago }
    end
  end
end
