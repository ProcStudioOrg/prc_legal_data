# app/controllers/api/v1/societies_controller.rb
module Api
  module V1
    class SocietiesController < ApplicationController
      include ApiAuthentication
      include UsageTracking
      include CrmParams

      before_action :authorize_write!, only: [ :create_society, :update_society, :update_crm, :destroy ]
      before_action :set_society, only: [:show, :update_society, :update_crm, :destroy]

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

      # --- Update CRM data action ---
      #
      # Espelha LawyersController#update_crm: grava no jsonb `crm_data` com
      # deep-merge, aceitando os sub-hashes livres :scraper, :outreach e :signals
      # produzidos pelo scraper de IA.
      def update_crm
        unless @society
          render json: { error: "Sociedade não encontrada" }, status: :not_found
          return
        end

        crm_params = params.permit(
          :researched, :last_research_date,
          :tried_procstudio, :mail_marketing, :contacted,
          :contacted_by, :contacted_when, :contact_notes,
          mail_marketing_origin: []
        ).to_h

        # Free-form deep-permit for AI-driven sub-hashes.
        merge_freeform_crm_keys(crm_params)

        if crm_params.empty?
          render json: { error: "Nenhum parâmetro CRM fornecido" }, status: :bad_request
          return
        end

        begin
          current_crm = @society.crm_data || {}
          new_crm = current_crm.deep_merge(crm_params.compact)

          if @society.update(crm_data: new_crm)
            render json: {
              message: "Dados CRM atualizados com sucesso",
              inscricao: @society.inscricao,
              oab_id: @society.oab_id,
              crm_data: @society.crm_data
            }, status: :ok
          else
            render json: {
              error: "Erro ao atualizar dados CRM",
              details: @society.errors.full_messages
            }, status: :unprocessable_entity
          end
        rescue => e
          Rails.logger.error("Error updating CRM for society #{@society.id}: #{e.message}")
          error_details = Rails.env.production? ? nil : { message: e.message, backtrace: e.backtrace&.first(5) }
          render json: {
            error: "Erro interno ao atualizar dados CRM",
            details: error_details
          }, status: :internal_server_error
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

      # O parâmetro aceita os dois identificadores: a inscrição OAB (numérica,
      # origem CNA) e o oab_id no formato MG_206787_SOCIEDADE, que é a chave das
      # sociedades vindas do portal da OAB-MG — elas não têm inscrição.
      def set_society
        key = params[:inscricao]
        return if key.blank?

        @society = if key.to_s.match?(/\A\d+\z/)
                     Society.find_by(inscricao: key)
                   else
                     Society.from_oab_portal.find_by(oab_id: key)
                   end
      end

      # Strong parameters for society creation
      def society_create_params
        params.permit(
          :inscricao, :name, :state, :oab_id, :address, :zip_code, :city,
          :phone, :phone_number_2, :number_of_partners, :situacao, :society_link,
          :email, :website, :cnpj, :source
        )
      end

      # Strong parameters for society updates
      def society_update_params
        params.permit(
          :name, :state, :oab_id, :address, :zip_code, :city,
          :phone, :phone_number_2, :number_of_partners, :situacao, :society_link,
          :email, :website, :cnpj, :source
        )
      end
    end
  end
end
