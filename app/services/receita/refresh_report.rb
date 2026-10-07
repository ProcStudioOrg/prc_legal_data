# frozen_string_literal: true

require 'net/http'

module Receita
  # POST do resumo de um refresh para o webhook do FFD (mesmo destino do
  # UsageReportJob). Aparece na página Alertas. Nunca levanta: falha aqui não
  # pode desfazer um refresh que já deu certo.
  module RefreshReport
    def self.call(release:, stats:, webhook_url: ENV['USAGE_WEBHOOK_URL'])
      return false if webhook_url.blank?

      payload = { service: 'legal_data', event: 'receita_refresh', release: release,
                  at: Time.current.iso8601, stats: stats }
      uri = URI(webhook_url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 30) do |http|
        http.post(uri.request_uri, payload.to_json, { 'Content-Type' => 'application/json' })
      end
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      Rails.logger.error("Receita::RefreshReport: #{e.class}: #{e.message}")
      false
    end
  end
end
