FactoryBot.define do
  factory :api_key do
    association :user
    sequence(:key) { |n| SecureRandom.hex(24) }
    active { true }

    trait :inactive do
      active { false }
    end
  end
end
