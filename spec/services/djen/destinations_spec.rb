require 'rails_helper'

RSpec.describe Djen::Destinations do
  def configured(env)
    described_class.configured(env)
  end

  it "parses PROCSTUDIO_DESTINATIONS as a comma-separated list of base_url|token" do
    env = { "PROCSTUDIO_DESTINATIONS" => "https://api-hml.example.com|tok-hml, https://api.example.com/|tok-prod" }

    destinations = configured(env)

    expect(destinations.map(&:base_url)).to eq(%w[https://api-hml.example.com https://api.example.com])
    expect(destinations.map(&:token)).to eq(%w[tok-hml tok-prod])
  end

  it "falls back to the legacy PROCSTUDIO_BASE_URL + INTEGRATION_DJEN_TOKEN pair" do
    env = { "PROCSTUDIO_BASE_URL" => "https://api-hml.example.com/", "INTEGRATION_DJEN_TOKEN" => "tok" }

    expect(configured(env)).to eq([ Djen::Destination.new(base_url: "https://api-hml.example.com", token: "tok") ])
  end

  it "ignores the legacy pair when PROCSTUDIO_DESTINATIONS is set" do
    env = {
      "PROCSTUDIO_DESTINATIONS" => "https://api.example.com|tok-prod",
      "PROCSTUDIO_BASE_URL" => "https://api-hml.example.com", "INTEGRATION_DJEN_TOKEN" => "tok-hml"
    }

    expect(configured(env).map(&:base_url)).to eq(%w[https://api.example.com])
  end

  it "returns an empty list when nothing is configured" do
    expect(configured({})).to eq([])
    expect(configured({ "PROCSTUDIO_BASE_URL" => "https://x.example.com" })).to eq([])
  end

  it "rejects malformed entries instead of silently dropping a destination" do
    expect { configured({ "PROCSTUDIO_DESTINATIONS" => "https://api.example.com" }) }
      .to raise_error(Djen::Destinations::ConfigurationError, /base_url\|token/)
    expect { configured({ "PROCSTUDIO_DESTINATIONS" => "api.example.com|tok" }) }
      .to raise_error(Djen::Destinations::ConfigurationError, /https?:\/\//)
    expect { configured({ "PROCSTUDIO_DESTINATIONS" => "https://a.example.com|t1,https://a.example.com/|t2" }) }
      .to raise_error(Djen::Destinations::ConfigurationError, /duplicado/)
  end

  it "identifies a destination by its normalized base_url" do
    destination = Djen::Destination.new(base_url: "https://API.example.com/", token: "t")

    expect(destination.key).to eq("https://api.example.com")
  end
end
