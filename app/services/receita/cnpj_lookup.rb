# frozen_string_literal: true

module Receita
  # Lookup de um CNPJ qualquer: primeiro a tabela (dump ou cache da API), depois
  # a API pública. Linha da API vale 30 dias; "não existe" vale 7 dias (cache
  # negativo = linha com raw vazio). Falha de rede/429 nunca grava nada.
  class CnpjLookup
    API_TTL = 30.days
    NEGATIVE_TTL = 7.days

    Result = Struct.new(:status, :company, :retry_after, keyword_init: true)

    def self.call(input, client: OpencnpjClient.new)
      new(input, client: client).call
    end

    def initialize(input, client:)
      @cnpj = Cnpj.normalize(input)
      @client = client
    end

    def call
      return Result.new(status: :invalid) if @cnpj.nil?

      cached = ReceitaCompany.find_by(cnpj: @cnpj)
      return result_for(cached) if cached && fresh?(cached)

      refresh_from_api
    end

    private

    def fresh?(company)
      return true if company.source == ReceitaCompany::SOURCE_DUMP

      ttl = company.negative_cache? ? NEGATIVE_TTL : API_TTL
      company.fetched_at > ttl.ago
    end

    def result_for(company)
      return Result.new(status: :not_found) if company.negative_cache?

      Result.new(status: :found, company: company)
    end

    def refresh_from_api
      record = @client.fetch(@cnpj)
      if record.nil?
        store_negative
        return Result.new(status: :not_found)
      end

      Importer.new(file: nil, release: nil, source: ReceitaCompany::SOURCE_API, logger: Rails.logger)
              .import_records([ record.merge("cnpj" => @cnpj) ])
      Result.new(status: :found, company: ReceitaCompany.find_by!(cnpj: @cnpj))
    rescue OpencnpjClient::RateLimited => e
      Result.new(status: :unavailable, retry_after: e.retry_after)
    rescue OpencnpjClient::Error => e
      Rails.logger.warn("Receita::CnpjLookup #{@cnpj}: #{e.message}")
      Result.new(status: :unavailable)
    end

    def store_negative
      now = Time.current
      ReceitaCompany.upsert_all(
        [ { cnpj: @cnpj, cnpj_root: @cnpj[0, 8], raw: {}, source: ReceitaCompany::SOURCE_API, release: nil,
           fetched_at: now, created_at: now, updated_at: now, telefones: [] } ],
        unique_by: :index_receita_companies_on_cnpj,
        update_only: %i[raw source release fetched_at]
      )
    end
  end
end
