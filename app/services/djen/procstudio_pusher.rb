require "net/http"

module Djen
  # Delivers pending intimações to every configured ProcStudio (Destinations).
  # At-least-once per destination: a DjenDelivery row is only stamped after
  # THAT destination's 2xx, and ProcStudio's endpoint is idempotent by djen_id,
  # so a retried lote never duplicates anything.
  #
  # Entrega em lotes de BATCH_SIZE: um backfill de 60 dias com `texto` completo
  # não pode virar um único POST gigante que estoura limite de body e envenena
  # todo retry. Cada lote é carimbado após o seu próprio 2xx, então progresso
  # parcial sobrevive a uma falha no meio.
  #
  # Um destino fora do ar não segura os outros: cada um recebe o que lhe falta
  # e só depois o erro sobe, para o job re-tentar. Na re-tentativa os destinos
  # saudáveis já não têm nada pendente.
  class ProcstudioPusher
    DeliveryError = Class.new(StandardError)

    ENDPOINT_PATH = "/api/v1/integracoes/djen/intimacoes".freeze
    BATCH_SIZE = 100

    def initialize(monitoring, destinations: Destinations.configured)
      @monitoring = monitoring
      @destinations = destinations
    end

    def call
      if @destinations.empty?
        raise DeliveryError, "nenhum destino configurado: defina #{Destinations::ENV_VAR} " \
                             "(base_url|token,...) ou o par legado PROCSTUDIO_BASE_URL + INTEGRATION_DJEN_TOKEN"
      end

      results = []
      failures = []
      @destinations.each do |destination|
        results << deliver_to(destination)
      rescue DeliveryError => e
        failures << "#{destination.key}: #{e.message}"
      end

      if failures.any?
        raise DeliveryError, "entrega falhou em #{failures.size} destino(s) — #{failures.join('; ')}"
      end

      results.include?(:pushed) ? :pushed : :nothing_to_push
    end

    private

    def deliver_to(destination)
      novas = @monitoring.djen_comunicacoes.pending_push_to(destination)
                         .order(:data_disponibilizacao, :id).to_a
      canceladas = @monitoring.djen_comunicacoes.pending_cancellation_push_to(destination).to_a
      return :nothing_to_push if novas.empty? && canceladas.empty?

      novas.each_slice(BATCH_SIZE) { |lote| push_lote(destination, novas: lote, canceladas: []) }
      canceladas.each_slice(BATCH_SIZE) { |lote| push_lote(destination, novas: [], canceladas: lote) }

      Rails.logger.info(
        "Djen: pushed lote to #{destination.key} for #{@monitoring.lawyer.oab_id} " \
        "(novas=#{novas.size} canceladas=#{canceladas.size})"
      )
      :pushed
    end

    def push_lote(destination, novas:, canceladas:)
      payload = LoteBuilder.new(@monitoring).call(novas: novas, canceladas: canceladas)
      response = post(destination, payload)

      unless response.code.to_i.between?(200, 299)
        raise DeliveryError, "ProcStudio responded #{response.code}: #{response.body&.first(200)}"
      end

      stamp(destination, novas, canceladas)
    end

    def stamp(destination, novas, canceladas)
      now = Time.current

      if novas.any?
        rows = novas.map do |c|
          {
            djen_comunicacao_id: c.id,
            destination: destination.key,
            pushed_at: now,
            # Cancelled before it was ever pushed: it went out once, as a "nova"
            # with ativo=false — no separate "cancelada" event needed.
            cancellation_pushed_at: (now if c.cancelled?),
            created_at: now,
            updated_at: now
          }
        end
        DjenDelivery.upsert_all(rows, unique_by: [ :djen_comunicacao_id, :destination ])
      end

      if canceladas.any?
        DjenDelivery.to(destination).where(djen_comunicacao_id: canceladas.map(&:id))
                    .update_all(cancellation_pushed_at: now, updated_at: now)
      end
    end

    def post(destination, payload)
      uri = URI("#{destination.base_url}#{ENDPOINT_PATH}")
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: 10, read_timeout: 60) do |http|
        http.post(uri.request_uri, payload.to_json,
                  { "Content-Type" => "application/json", "Authorization" => "Bearer #{destination.token}" })
      end
    rescue SystemCallError, Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError => e
      raise DeliveryError, "ProcStudio push failed: #{e.class}: #{e.message}"
    end
  end
end
