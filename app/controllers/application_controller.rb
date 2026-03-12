class ApplicationController < ActionController::API
  include ApiErrorHandler

  # Enable request_id in the logs for correlation
  before_action :set_request_id

  private

  def set_request_id
    request_id = request.request_id || SecureRandom.uuid
    RequestStore.store[:request_id] = request_id
    # Also set for tagged logging
    Rails.logger.push_tags(request_id) if Rails.logger.respond_to?(:push_tags)
  end
end
