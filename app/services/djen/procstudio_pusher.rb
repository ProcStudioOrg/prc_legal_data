require "net/http"

module Djen
  # Delivers pending intimações to ProcStudio. At-least-once: rows are only
  # stamped after a 2xx, and ProcStudio's endpoint is idempotent by djen_id,
  # so a retried lote never duplicates anything.
  class ProcstudioPusher
    DeliveryError = Class.new(StandardError)

    ENDPOINT_PATH = "/api/v1/integracoes/djen/intimacoes".freeze

    def initialize(monitoring,
                   base_url: ENV["PROCSTUDIO_BASE_URL"],
                   token: ENV["INTEGRATION_DJEN_TOKEN"])
      @monitoring = monitoring
      @base_url = base_url
      @token = token
    end

    def call
      novas = @monitoring.djen_comunicacoes.pending_push.order(:data_disponibilizacao).to_a
      canceladas = @monitoring.djen_comunicacoes.pending_cancellation_push.to_a
      return :nothing_to_push if novas.empty? && canceladas.empty?

      raise DeliveryError, "PROCSTUDIO_BASE_URL not configured" if @base_url.blank?

      payload = LoteBuilder.new(@monitoring).call(novas: novas, canceladas: canceladas)
      response = post(payload)

      unless response.code.to_i.between?(200, 299)
        raise DeliveryError, "ProcStudio responded #{response.code}: #{response.body&.first(200)}"
      end

      stamp(novas, canceladas)
      Rails.logger.info(
        "Djen: pushed lote to ProcStudio for #{@monitoring.lawyer.oab_id} " \
        "(novas=#{novas.size} canceladas=#{canceladas.size})"
      )
      :pushed
    end

    private

    def stamp(novas, canceladas)
      now = Time.current
      novas.each do |c|
        updates = { pushed_at: now }
        # Cancelled before it was ever pushed: it goes out once, as a "nova"
        # with ativo=false — no separate "cancelada" event needed.
        updates[:cancellation_pushed_at] = now if c.cancelled?
        c.update!(updates)
      end
      canceladas.each { |c| c.update!(cancellation_pushed_at: now) }
    end

    def post(payload)
      uri = URI("#{@base_url}#{ENDPOINT_PATH}")
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: 10, read_timeout: 60) do |http|
        http.post(uri.request_uri, payload.to_json,
                  { "Content-Type" => "application/json", "Authorization" => "Bearer #{@token}" })
      end
    rescue SystemCallError, Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError => e
      raise DeliveryError, "ProcStudio push failed: #{e.class}: #{e.message}"
    end
  end
end
