require 'rails_helper'

RSpec.describe DjenDelivery, type: :model do
  it "is unique per comunicação and destination" do
    existing = create(:djen_delivery)
    duplicate = build(:djen_delivery, djen_comunicacao: existing.djen_comunicacao,
                                      destination: existing.destination)

    expect(duplicate).not_to be_valid
  end

  it "accepts a Destination or a string as the destination key" do
    delivery = create(:djen_delivery, destination: "https://api.example.com")
    destination = Djen::Destination.new(base_url: "https://api.example.com/", token: "t")

    expect(described_class.to(destination)).to contain_exactly(delivery)
    expect(described_class.to("https://api.example.com")).to contain_exactly(delivery)
  end
end
