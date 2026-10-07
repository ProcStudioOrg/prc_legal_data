# frozen_string_literal: true

require 'net/http'
require 'json'

module Receita
  # API pública do OpenCNPJ (mesmo JSON do dump). Sem chave. Limite público não
  # documentado: 1 tentativa por CNPJ, timeouts curtos, e quem chama decide o
  # cache. A própria API manda Cache-Control de 24h.
  class OpencnpjClient
    HOST = 'api.opencnpj.org'
    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 5

    class Error < StandardError; end

    class RateLimited < Error
      attr_reader :retry_after

      def initialize(retry_after)
        @retry_after = retry_after
        super("OpenCNPJ 429, retry em #{retry_after}s")
      end
    end

    # Hash do estabelecimento, ou nil quando a Receita não conhece o CNPJ (404).
    def fetch(cnpj)
      uri = URI::HTTPS.build(host: HOST, path: "/#{cnpj}")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.get(uri.request_uri, { 'Accept' => 'application/json', 'User-Agent' => 'legal_data (procstudio.api.br)' })
      end

      case response
      when Net::HTTPSuccess then parse_body(response.body)
      when Net::HTTPNotFound then nil
      when Net::HTTPTooManyRequests then raise RateLimited, response['Retry-After'].to_i.clamp(1, 3600)
      else raise Error, "OpenCNPJ HTTP #{response.code}"
      end
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError, EOFError,
           Net::ProtocolError, Net::HTTPBadResponse, OpenSSL::SSL::SSLError => e
      raise Error, "#{e.class}: #{e.message}"
    end

    private

    def parse_body(body)
      parsed = JSON.parse(body)
      raise Error, 'OpenCNPJ: corpo inesperado' unless parsed.is_a?(Hash)

      parsed
    end
  end
end
