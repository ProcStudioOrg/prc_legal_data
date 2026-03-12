# app/controllers/api/v1/societies_controller.rb
module Api
  module V1
    class SocietiesController < ApplicationController
      # --- Existing before_action/after_action filters ---
      before_action :authenticate_with_api_key
      before_action :set_request_start_time
      before_action :set_society, only: [:show, :update_society, :destroy]
      after_action :log_api_request

      # --- Create society action ---
      def create_society
        # 1. Validate the required parameters
        create_params = society_create_params

        # Check for required fields
        unless create_params[:inscricao].present? && create_params[:name].present? &&
               create_params[:state].present? && create_params[:number_of_partners].present?
          render json: { error: "Inscrição, Nome, Estado e Número de Sócios são obrigatórios" }, status: :bad_request
          return
        end

        # 2. Check if a society with this registration already exists
        if Society.exists?(inscricao: create_params[:inscricao])
          render json: {
            error: "Sociedade com inscrição #{create_params[:inscricao]} já cadastrada",
            society_id: Society.find_by(inscricao: create_params[:inscricao]).id
          }, status: :conflict
          return
        end

        # 3. Build the society object with all parameters
        @society = Society.new(create_params)

        # Format the OAB ID if needed
        if @society.oab_id.blank? && @society.state.present?
          @society.oab_id = "#{@society.state.upcase}_SOC_#{@society.inscricao}"
        end

        begin
          # 4. Save the society
          if @society.save
            render json: {
              message: "Sociedade criada com sucesso",
              society: @society.as_json
            }, status: :created
          else
            render json: {
              error: "Erro ao criar sociedade",
              details: @society.errors.full_messages
            }, status: :unprocessable_entity
          end
        rescue => e
          Rails.logger.error("Error creating society with inscricao #{create_params[:inscricao]}: #{e.message}")
          render json: { error: "Erro interno ao criar sociedade" }, status: :internal_server_error
        end
      end

      # --- Show society action ---
      def show
        if @society
          render json: SocietySerializer.new(@society, include_lawyers: true).as_json, status: :ok
        else
          render json: { error: "Sociedade não encontrada" }, status: :not_found
        end
      end

      # --- Update society action ---
      def update_society
        unless @society
          render json: { error: "Sociedade não encontrada" }, status: :not_found
          return
        end

        # Get the update parameters from the request
        update_params = society_update_params

        if update_params.empty?
          render json: { error: "Nenhum parâmetro de atualização fornecido" }, status: :bad_request
          return
        end

        begin
          if @society.update(update_params)
            render json: {
              message: "Sociedade atualizada com sucesso",
              society: @society.as_json
            }, status: :ok
          else
            render json: {
              error: "Erro ao atualizar sociedade",
              details: @society.errors.full_messages
            }, status: :unprocessable_entity
          end
        rescue => e
          Rails.logger.error("Error updating society #{@society.id}: #{e.message}")
          render json: { error: "Erro interno ao atualizar sociedade" }, status: :internal_server_error
        end
      end

      # --- Destroy society action ---
      def destroy
        unless @society
          render json: { error: "Sociedade não encontrada" }, status: :not_found
          return
        end

        begin
          society_info = {
            id: @society.id,
            inscricao: @society.inscricao,
            name: @society.name,
            lawyers_removed: @society.lawyers.count
          }

          # This will cascade delete all LawyerSociety records due to dependent: :destroy
          @society.destroy!

          render json: {
            message: "Sociedade excluída com sucesso",
            deleted_society: society_info
          }, status: :ok
        rescue ActiveRecord::RecordNotDestroyed => e
          Rails.logger.error("Error destroying society #{@society.id}: #{e.message}")
          render json: {
            error: "Erro ao excluir sociedade",
            details: @society.errors.full_messages
          }, status: :unprocessable_entity
        rescue => e
          Rails.logger.error("Error destroying society #{@society.id}: #{e.message}")
          error_details = Rails.env.production? ? nil : { message: e.message }
          render json: {
            error: "Erro interno ao excluir sociedade",
            details: error_details
          }, status: :internal_server_error
        end
      end

      # --- Private methods ---
      private

      def set_society
        inscricao = params[:inscricao]
        @society = Society.find_by(inscricao: inscricao) if inscricao.present?
      end

      def set_request_start_time
        @request_start_time = Time.now
      end

      def authenticate_with_api_key
        api_key = request.headers["X-API-KEY"]
        @api_key = ApiKey.find_by(key: api_key, active: true)

        unless @api_key
          render json: { error: "Invalid API Key" }, status: :unauthorized
          return
        end

        @current_user = @api_key.user
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
          requested_oab: params[:inscricao]
        )
      rescue => e
        Rails.logger.error("Failed to log API request: #{e.message}")
      end

      # Strong parameters for society creation
      def society_create_params
        params.permit(
          :inscricao, :name, :state, :oab_id, :address, :zip_code, :city,
          :phone, :phone_number_2, :number_of_partners, :situacao, :society_link
        )
      end

      # Strong parameters for society updates
      def society_update_params
        params.permit(
          :name, :state, :oab_id, :address, :zip_code, :city,
          :phone, :phone_number_2, :number_of_partners, :situacao, :society_link
        )
      end
    end
  end
end
