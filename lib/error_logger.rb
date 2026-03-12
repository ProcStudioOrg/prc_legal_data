# lib/error_logger.rb
module ErrorLogger
  class << self
    # Log an exception with detailed information
    # @param exception [Exception] The exception to log
    # @param context [Hash] Additional context for the error
    # @param level [Symbol] The log level (default: :error)
    # @return [void]
    def log_exception(exception, context = {}, level = :error)
      return unless exception.is_a?(Exception)

      error_data = {
        error_class: exception.class.name,
        error_message: exception.message,
        timestamp: Time.current.utc.iso8601(3),
        backtrace: exception.backtrace&.first(15)
      }

      # Add request information if available
      if defined?(RequestStore) && RequestStore.store[:request_id]
        error_data[:request_id] = RequestStore.store[:request_id]
      end

      # Merge any additional context
      error_data.merge!(context) if context.is_a?(Hash)

      # Format the error message
      formatted_message = format_error_message(error_data)

      # Log using Rails logger with tags
      Rails.logger.tagged('ErrorLogger', error_data[:error_class]) do
        Rails.logger.send(level, formatted_message)
      end
    end

    # Log an API error with detailed information about the request
    # @param exception [Exception] The exception to log
    # @param controller [ActionController::Base] The controller instance
    # @param level [Symbol] The log level (default: :error)
    # @return [void]
    def log_api_error(exception, controller, level = :error)
      return unless exception.is_a?(Exception) && controller.is_a?(ActionController::Base)

      request = controller.request
      context = {
        controller: controller.class.name,
        action: controller.action_name,
        http_method: request.method,
        path: request.path,
        params: request.filtered_parameters.except('controller', 'action'),
        remote_ip: request.remote_ip,
        user_agent: request.user_agent,
        request_id: request.request_id || RequestStore.store[:request_id]
      }

      # Add current user info if available
      if controller.respond_to?(:current_user) && controller.current_user
        context[:user_id] = controller.current_user.id
      end

      # Use API tag for API errors
      Rails.logger.tagged('API') do
        log_exception(exception, context, level)
      end
    end

    # Helper method to log database errors specifically
    # @param exception [Exception] The database exception
    # @param model [ActiveRecord::Base] The model involved (optional)
    # @param context [Hash] Additional context (optional)
    # @return [void]
    def log_db_error(exception, model = nil, context = {})
      return unless exception.is_a?(Exception)

      error_context = context.dup

      # Add model information if available
      if model.is_a?(ActiveRecord::Base)
        error_context[:model_class] = model.class.name
        error_context[:model_id] = model.id if model.respond_to?(:id) && model.id.present?
        error_context[:model_errors] = model.errors.full_messages if model.errors.any?
        error_context[:model_attributes] = model.attributes.except('created_at', 'updated_at')
      end

      # Use DB tag for database errors
      Rails.logger.tagged('DATABASE') do
        log_exception(exception, error_context, :error)
      end
    end

    private

    # Format error message for logging
    # @param error_data [Hash] The error data to format
    # @return [String] The formatted error message
    def format_error_message(error_data)
      # Base message with error class and message
      message = "[ERROR] #{error_data[:error_class]}: #{error_data[:error_message]}"

      # Add request_id if available
      if error_data[:request_id]
        message = "[#{error_data[:request_id]}] #{message}"
      end

      # Add context information
      context_info = error_data.except(:error_class, :error_message, :backtrace, :request_id)
      unless context_info.empty?
        context_str = context_info.map { |k, v| "#{k}: #{v.inspect}" }.join(', ')
        message += " | Context: { #{context_str} }"
      end

      # Add backtrace if available
      if error_data[:backtrace] && !error_data[:backtrace].empty?
        message += "\nBacktrace:\n  #{error_data[:backtrace].join("\n  ")}"
      end

      message
    end
  end
end
