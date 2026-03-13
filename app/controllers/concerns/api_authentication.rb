module ApiAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_with_api_key
    before_action :set_request_start_time
    after_action :log_api_request
  end

  private

  def authenticate_with_api_key
    api_key = request.headers["X-API-KEY"]
    @api_key = ApiKey.find_by(key: api_key, active: true)

    unless @api_key
      render json: {
        error: "Invalid API Key",
        request_id: RequestStore.store[:request_id]
      }, status: :unauthorized
      return
    end

    @current_user = @api_key.user
  end

  def authorize_write!
    return if @api_key&.admin?

    render json: {
      error: "Forbidden: read-only API key",
      request_id: RequestStore.store[:request_id]
    }, status: :forbidden
  end

  def set_request_start_time
    @request_start_time = Time.now
    RequestStore.store[:request_id] = request.request_id || SecureRandom.uuid

    if request.content_type.blank? && request.headers["Content-Type"].blank? && request.post?
      request.headers["Content-Type"] = "application/json"
    end
  end

  def log_api_request
    country_code = Geocoder.search(request.ip).first&.country_code

    ApiLog.create(
      user_id: @current_user&.id,
      api_key_id: @api_key&.id,
      endpoint: request.path,
      ip_address: request.ip,
      request_method: request.method,
      response_status: response.status,
      request_size: request.content_length || 0,
      response_time: (Time.now - @request_start_time),
      country_code: country_code,
      browser: request.user_agent,
      requested_oab: params[:oab] || params[:inscricao] || params[:state]
    )
  rescue => e
    Rails.logger.error("Failed to log API request: #{e.message}")
  end
end
