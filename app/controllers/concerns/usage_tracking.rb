require "digest"

# Grava um UsageEvent por consulta (GET) ao banco de advogados/sociedades.
# Fire-and-forget: qualquer erro é logado e engolido — o tracking nunca pode
# afetar a resposta da request. Não reutiliza o ApiLog de propósito: aqui o IP
# vai hasheado com salt (LGPD), em tabela própria consumida pelo UsageReportJob.
#
# Nota: requests barradas pela auth (before_action renderiza 401/403) halteiam
# a callback chain, então o after_action não roda — só consultas autenticadas
# são contadas.
module UsageTracking
  extend ActiveSupport::Concern

  EVENT_TYPE = "consulta".freeze

  included do
    after_action :track_usage_event
  end

  private

  def track_usage_event
    return unless request.get?

    UsageEvent.create!(event_type: EVENT_TYPE, ip_hash: usage_ip_hash)
  rescue StandardError => e
    Rails.logger.error("UsageTracking: failed to record usage event: #{e.class}: #{e.message}")
  end

  def usage_ip_hash
    forwarded_ip = request.headers["X-Forwarded-For"].to_s.split(",").first&.strip
    ip = forwarded_ip.presence || request.remote_ip
    Digest::SHA256.hexdigest(ip.to_s + ENV["USAGE_IP_SALT"].to_s)
  end
end
