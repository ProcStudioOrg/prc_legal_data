FactoryBot.define do
  factory :djen_delivery do
    association :djen_comunicacao
    destination { "https://procstudio.example.com" }
    pushed_at { 1.hour.ago }
  end
end
