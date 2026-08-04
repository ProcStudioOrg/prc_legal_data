FactoryBot.define do
  factory :api_key do
    association :user
    sequence(:key) { |n| SecureRandom.hex(24) }
    active { true }
    # Espelha o default do banco (`role` default "read", null: false). Escrita
    # exige `admin` — use a trait, senão o endpoint responde 403.
    role { 'read' }

    trait :admin do
      role { 'admin' }
    end

    trait :inactive do
      active { false }
    end
  end
end
