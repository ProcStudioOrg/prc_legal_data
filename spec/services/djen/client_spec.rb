require 'rails_helper'

RSpec.describe Djen::Client do
  let(:base_url) { "https://comunicaapi.pje.jus.br" }
  let(:rate_limiter) do
    instance_double(Djen::RateLimiter, acquire!: nil, update_from_headers: nil, throttle!: nil)
  end
  let(:sleeps) { [] }
  let(:client) do
    described_class.new(rate_limiter: rate_limiter, sleeper: ->(s) { sleeps << s })
  end

  def stub_page(pagina:, items:, status: 200)
    stub_request(:get, "#{base_url}/api/v1/comunicacao")
      .with(query: hash_including("pagina" => pagina.to_s))
      .to_return(status: status, body: djen_page(items).to_json)
  end

  describe "#each_comunicacao" do
    it "paginates until an empty page" do
      stub_page(pagina: 1, items: [ djen_item("id" => 1), djen_item("id" => 2) ])
      stub_page(pagina: 2, items: [ djen_item("id" => 3) ])
      stub_page(pagina: 3, items: [])

      ids = client.each_comunicacao(numero_oab: "54159", uf_oab: "PR",
                                    data_inicio: Date.new(2026, 7, 1),
                                    data_fim: Date.new(2026, 7, 10)).map { |i| i["id"] }

      expect(ids).to eq([ 1, 2, 3 ])
    end

    it "sends the OAB and date window as query params" do
      stub = stub_request(:get, "#{base_url}/api/v1/comunicacao")
        .with(query: {
          "numeroOab" => "54159", "ufOab" => "PR",
          "dataDisponibilizacaoInicio" => "2026-07-01", "dataDisponibilizacaoFim" => "2026-07-10",
          "itensPorPagina" => "100", "pagina" => "1"
        })
        .to_return(status: 200, body: djen_page([]).to_json)

      client.each_comunicacao(numero_oab: "54159", uf_oab: "PR",
                              data_inicio: Date.new(2026, 7, 1),
                              data_fim: Date.new(2026, 7, 10)).to_a

      expect(stub).to have_been_requested
    end

    it "backs off and retries on 429" do
      stub_request(:get, "#{base_url}/api/v1/comunicacao")
        .with(query: hash_including("pagina" => "1"))
        .to_return({ status: 429 }, { status: 200, body: djen_page([]).to_json })

      result = client.each_comunicacao(numero_oab: "54159", uf_oab: "PR",
                                       data_inicio: Date.new(2026, 7, 1),
                                       data_fim: Date.new(2026, 7, 10)).to_a

      expect(result).to eq([])
      expect(sleeps.first).to be >= described_class::RATE_LIMIT_WAIT
      expect(rate_limiter).to have_received(:throttle!)
    end

    it "raises Error after exhausting 429 retries instead of looping forever" do
      stub_request(:get, "#{base_url}/api/v1/comunicacao")
        .with(query: hash_including("pagina" => "1"))
        .to_return(status: 429)

      expect {
        client.each_comunicacao(numero_oab: "54159", uf_oab: "PR",
                                data_inicio: Date.new(2026, 7, 1),
                                data_fim: Date.new(2026, 7, 10)).to_a
      }.to raise_error(Djen::Client::Error, /rate-limiting/)

      expect(sleeps.size).to eq(described_class::RATE_LIMIT_RETRIES)
    end

    it "wraps invalid JSON in Client::Error" do
      stub_request(:get, "#{base_url}/api/v1/comunicacao")
        .with(query: hash_including("pagina" => "1"))
        .to_return(status: 200, body: "<html>gateway</html>")

      expect {
        client.each_comunicacao(numero_oab: "54159", uf_oab: "PR",
                                data_inicio: Date.new(2026, 7, 1),
                                data_fim: Date.new(2026, 7, 10)).to_a
      }.to raise_error(Djen::Client::Error, /invalid JSON/)
    end

    it "rejects a 200 whose body is not the expected object shape" do
      stub_request(:get, "#{base_url}/api/v1/comunicacao")
        .with(query: hash_including("pagina" => "1"))
        .to_return(status: 200, body: "null")

      expect {
        client.each_comunicacao(numero_oab: "54159", uf_oab: "PR",
                                data_inicio: Date.new(2026, 7, 1),
                                data_fim: Date.new(2026, 7, 10)).to_a
      }.to raise_error(Djen::Client::Error, /non-object body/)
    end

    it "wraps network failures in Client::Error" do
      stub_request(:get, "#{base_url}/api/v1/comunicacao")
        .with(query: hash_including("pagina" => "1"))
        .to_timeout

      expect {
        client.each_comunicacao(numero_oab: "54159", uf_oab: "PR",
                                data_inicio: Date.new(2026, 7, 1),
                                data_fim: Date.new(2026, 7, 10)).to_a
      }.to raise_error(Djen::Client::Error, /request failed/)
    end

    it "raises immediately on an unexpected 4xx" do
      stub_request(:get, "#{base_url}/api/v1/comunicacao")
        .with(query: hash_including("pagina" => "1"))
        .to_return(status: 403, body: "forbidden")

      expect {
        client.each_comunicacao(numero_oab: "54159", uf_oab: "PR",
                                data_inicio: Date.new(2026, 7, 1),
                                data_fim: Date.new(2026, 7, 10)).to_a
      }.to raise_error(Djen::Client::Error, /unexpected response 403/)

      expect(sleeps).to be_empty
    end

    it "raises ServerError after exhausting 5xx retries" do
      stub_request(:get, "#{base_url}/api/v1/comunicacao")
        .with(query: hash_including("pagina" => "1"))
        .to_return(status: 500)

      expect {
        client.each_comunicacao(numero_oab: "54159", uf_oab: "PR",
                                data_inicio: Date.new(2026, 7, 1),
                                data_fim: Date.new(2026, 7, 10)).to_a
      }.to raise_error(Djen::Client::ServerError)

      expect(sleeps.size).to eq(described_class::SERVER_ERROR_RETRIES)
    end

    it "acquires a rate limit slot before every request" do
      stub_page(pagina: 1, items: [ djen_item ])
      stub_page(pagina: 2, items: [])

      client.each_comunicacao(numero_oab: "54159", uf_oab: "PR",
                              data_inicio: Date.new(2026, 7, 1),
                              data_fim: Date.new(2026, 7, 10)).to_a

      expect(rate_limiter).to have_received(:acquire!).twice
    end
  end
end
