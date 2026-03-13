# app/controllers/api/v1/lawyer_societies_controller.rb
module Api
  module V1
    class LawyerSocietiesController < ApplicationController
      include ApiAuthentication

      before_action :authorize_write!, only: [ :create, :update, :destroy ]
      before_action :set_lawyer_society, only: [:show, :update, :destroy]

      # --- Create lawyer-society relationship action ---
      def create
        # 1. Validate the required parameters
        create_params = lawyer_society_params

        # Check for required fields
        unless create_params[:lawyer_id].present? && create_params[:society_id].present? &&
               create_params[:partnership_type].present?
          render json: { error: "Advogado, Sociedade e Tipo de Associação são obrigatórios" }, status: :bad_request
          return
        end

        # 2. Check if the lawyer exists
        lawyer = Lawyer.find_by(id: create_params[:lawyer_id])
        unless lawyer
          render json: { error: "Advogado não encontrado" }, status: :not_found
          return
        end

        # 3. Check if the society exists
        society = Society.find_by(id: create_params[:society_id])
        unless society
          render json: { error: "Sociedade não encontrada" }, status: :not_found
          return
        end

        # 4. Check if the relationship already exists
        if LawyerSociety.exists?(lawyer_id: create_params[:lawyer_id], society_id: create_params[:society_id])
          render json: {
            error: "Relação entre advogado e sociedade já existe",
            lawyer_society: LawyerSociety.find_by(
              lawyer_id: create_params[:lawyer_id],
              society_id: create_params[:society_id]
            ).as_json
          }, status: :conflict
          return
        end

        # 5. Create the lawyer-society relationship
        @lawyer_society = LawyerSociety.new(create_params)

        begin
          if @lawyer_society.save
            render json: {
              message: "Relação entre advogado e sociedade criada com sucesso",
              lawyer_society: @lawyer_society.as_json,
              society: society.as_json(only: [:id, :name, :inscricao]),
              lawyer: lawyer.as_json(only: [:id, :oab_id, :full_name])
            }, status: :created
          else
            render json: {
              error: "Erro ao criar relação entre advogado e sociedade",
              details: @lawyer_society.errors.full_messages
            }, status: :unprocessable_entity
          end
        rescue => e
          Rails.logger.error("Error creating lawyer-society relationship: #{e.message}")
          render json: { error: "Erro interno ao criar relação" }, status: :internal_server_error
        end
      end

      # --- Show lawyer-society relationship action ---
      def show
        if @lawyer_society
          render json: {
            lawyer_society: @lawyer_society.as_json,
            lawyer: @lawyer_society.lawyer.as_json(only: [:id, :oab_id, :full_name]),
            society: @lawyer_society.society.as_json(only: [:id, :name, :inscricao])
          }, status: :ok
        else
          render json: { error: "Relação entre advogado e sociedade não encontrada" }, status: :not_found
        end
      end

      # --- Update lawyer-society relationship action ---
      def update
        unless @lawyer_society
          render json: { error: "Relação entre advogado e sociedade não encontrada" }, status: :not_found
          return
        end

        # Get the update parameters from the request
        update_params = lawyer_society_update_params

        if update_params.empty?
          render json: { error: "Nenhum parâmetro de atualização fornecido" }, status: :bad_request
          return
        end

        begin
          if @lawyer_society.update(update_params)
            render json: {
              message: "Relação atualizada com sucesso",
              lawyer_society: @lawyer_society.as_json
            }, status: :ok
          else
            render json: {
              error: "Erro ao atualizar relação",
              details: @lawyer_society.errors.full_messages
            }, status: :unprocessable_entity
          end
        rescue => e
          Rails.logger.error("Error updating lawyer-society relationship #{@lawyer_society.id}: #{e.message}")
          render json: { error: "Erro interno ao atualizar relação" }, status: :internal_server_error
        end
      end

      # --- Delete lawyer-society relationship action ---
      def destroy
        unless @lawyer_society
          render json: { error: "Relação entre advogado e sociedade não encontrada" }, status: :not_found
          return
        end

        begin
          @lawyer_society.destroy

          render json: {
            message: "Relação entre advogado e sociedade removida com sucesso"
          }, status: :ok
        rescue => e
          Rails.logger.error("Error deleting lawyer-society relationship #{@lawyer_society.id}: #{e.message}")
          render json: { error: "Erro interno ao remover relação" }, status: :internal_server_error
        end
      end

      # --- Private methods ---
      private

      def set_lawyer_society
        id = params[:id]
        @lawyer_society = LawyerSociety.find_by(id: id) if id.present?
      end

      # Strong parameters for lawyer-society relationship
      def lawyer_society_params
        params.permit(
          :lawyer_id, :society_id, :partnership_type, :cna_link
        )
      end

      # Strong parameters for lawyer-society relationship updates
      def lawyer_society_update_params
        params.permit(
          :partnership_type, :cna_link
        )
      end
    end
  end
end
