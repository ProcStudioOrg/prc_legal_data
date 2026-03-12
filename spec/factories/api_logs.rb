FactoryBot.define do
  factory :api_log do
    user_id { 1 }
    api_key_id { 1 }
    endpoint { "MyString" }
    ip_address { "MyString" }
    request_method { "MyString" }
    response_status { 1 }
    request_size { 1 }
    response_time { 1.5 }
    country_code { "MyString" }
    browser { "MyString" }
  end
end
