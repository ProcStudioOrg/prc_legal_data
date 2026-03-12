# app/controllers/concerns/api_error_handler.rb
module ApiErrorHandler
  extend ActiveSupport::Concern

  included do
    rescue_from StandardError, with: :handle_standard_error
    rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :handle_record_invalid
    rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
  end

  private

  def handle_standard_error(exception)
    log_error(exception)

    render json: {
      error: "Erro interno do servidor",
      message: "Ocorreu um erro inesperado ao processar sua solicitação",
      error_type: exception.class.name,
      error_details: Rails.env.production? ? nil : exception.message,
      request_id: request.request_id
    }, status: :internal_server_error
  end

  def handle_record_not_found(exception)
    log_error(exception)

    render json: {
      error: "Recurso não encontrado",
      message: "O recurso solicitado não pôde ser encontrado",
      error_details: exception.message,
      request_id: request.request_id
    }, status: :not_found
  end

  def handle_record_invalid(exception)
    log_error(exception)

    render json: {
      error: "Dados inválidos",
      message: "Os dados fornecidos são inválidos",
      validation_errors: exception.record.errors.full_messages,
      request_id: request.request_id
    }, status: :unprocessable_entity
  end

  def handle_parameter_missing(exception)
    log_error(exception)

    render json: {
      error: "Parâmetro obrigatório ausente",
      message: "Um parâmetro obrigatório está ausente na solicitação",
      error_details: exception.message,
      request_id: request.request_id
    }, status: :bad_request
  end

  def log_error(exception)
    error_context = {
      error_class: exception.class.name,
      error_message: exception.message,
      request_id: request.request_id,
      request_path: request.path,
      request_method: request.method,
      request_params: request.filtered_parameters,
      client_ip: request.ip,
      user_agent: request.user_agent
    }

    if exception.backtrace
      error_context[:backtrace] = exception.backtrace[0..9] # First 10 lines of backtrace
    end

    Rails.logger.tagged("API", "ERROR") do
      Rails.logger.error("API Error: #{error_context.to_json}")
    end
  end
end
