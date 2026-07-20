require "net/http"

# Relatório diário de uso (config/recurring.yml, 00:05 America/Sao_Paulo).
# Agrega os UsageEvents do dia anterior (fuso de São Paulo) e faz POST para
# ENV["USAGE_WEBHOOK_URL"]. Envia mesmo com zero eventos — o payload zerado
# funciona como heartbeat do serviço.
class UsageReportJob < ApplicationJob
  DeliveryError = Class.new(StandardError)

  TIME_ZONE = "America/Sao_Paulo".freeze
  TOP_REPEATS_LIMIT = 5

  queue_as :default

  retry_on DeliveryError, wait: :polynomially_longer, attempts: 3 do |job, error|
    Rails.logger.error("UsageReportJob: giving up after 3 attempts: #{error.message}")
  end

  def perform(date = nil)
    webhook_url = ENV["USAGE_WEBHOOK_URL"]
    if webhook_url.blank?
      Rails.logger.warn("UsageReportJob: USAGE_WEBHOOK_URL not set, skipping report")
      return
    end

    date ||= Time.now.in_time_zone(TIME_ZONE).to_date - 1
    post_report(webhook_url, build_payload(date))
  end

  private

  def build_payload(date)
    tz = ActiveSupport::TimeZone[TIME_ZONE]
    day_start = tz.local(date.year, date.month, date.day)
    scope = UsageEvent.where(created_at: day_start...(day_start + 1.day))

    top_repeats = scope
      .group(:ip_hash)
      .having("COUNT(*) > 1")
      .order(Arel.sql("COUNT(*) DESC"))
      .limit(TOP_REPEATS_LIMIT)
      .count
      .map { |ip_hash, count| { user: ip_hash[0, 8], count: count } }

    {
      service: "legal_data",
      date: date.iso8601,
      events: scope.count,
      unique_users: scope.distinct.count(:ip_hash),
      top_repeats: top_repeats
    }
  end

  def post_report(webhook_url, payload)
    uri = URI(webhook_url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: 10, read_timeout: 30) do |http|
      http.post(uri.request_uri, payload.to_json, { "Content-Type" => "application/json" })
    end

    unless response.code.to_i.between?(200, 299)
      raise DeliveryError, "usage webhook responded #{response.code}: #{response.body&.first(200)}"
    end

    Rails.logger.info("UsageReportJob: report sent for #{payload[:date]} (events=#{payload[:events]})")
  rescue SystemCallError, Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError => e
    raise DeliveryError, "usage webhook POST failed: #{e.class}: #{e.message}"
  end
end
