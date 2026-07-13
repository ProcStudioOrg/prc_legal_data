module Api
  module V1
    module Djen
      class MonitoringsController < ApplicationController
        include ApiAuthentication

        # ProcStudio deliberately holds only a read API key (no admin key in the
        # app), so activating a watch is allowed to any active key. Deactivation
        # stays admin-only: silently pausing a watch means missed intimações.
        before_action :authorize_write!, only: [ :destroy ]
        before_action :set_principal_lawyer

        # POST /api/v1/djen/monitorings  { "oab": "PR_54159" }
        # Idempotent: re-activating an existing watch returns 200.
        def create
          retried = false
          begin
            monitoring = DjenMonitoring.find_or_initialize_by(lawyer: @principal)
            newly_created = monitoring.new_record?
            reactivating = !newly_created && !monitoring.active

            monitoring.active = true
            monitoring.source = params[:source].presence || monitoring.source || "procstudio"
            monitoring.save!
          rescue ActiveRecord::RecordNotUnique
            # POST concorrente criou o registro primeiro; idempotência exige reusar.
            raise if retried

            retried = true
            retry
          end

          # Só na criação/reativação: re-POSTs enquanto o onboarding ainda roda
          # não podem enfileirar backfills de 60 dias em duplicata.
          if !monitoring.onboarded? && (newly_created || reactivating)
            ::Djen::OnboardJob.perform_later(monitoring)
          end

          render json: DjenMonitoringSerializer.new(monitoring).as_json,
                 status: newly_created ? :created : :ok
        end

        # GET /api/v1/djen/monitorings/:oab
        def show
          monitoring = @principal.djen_monitoring
          unless monitoring
            render json: { error: "Advogado não monitorado no DJEN" }, status: :not_found
            return
          end

          render json: DjenMonitoringSerializer.new(monitoring).as_json, status: :ok
        end

        # DELETE /api/v1/djen/monitorings/:oab — pauses; history is kept.
        def destroy
          monitoring = @principal.djen_monitoring
          unless monitoring
            render json: { error: "Advogado não monitorado no DJEN" }, status: :not_found
            return
          end

          monitoring.update!(active: false)
          render json: DjenMonitoringSerializer.new(monitoring).as_json, status: :ok
        end

        private

        # Accepts any of the lawyer's OABs (principal or supplementary) and
        # resolves to the principal, so one person never gets two watches.
        def set_principal_lawyer
          oab = params[:oab]
          unless oab.is_a?(String) && oab.present?
            render json: { error: "OAB ID obrigatório (ex: PR_54159)" }, status: :bad_request
            return
          end

          lawyer = Lawyer.find_by(oab_id: oab)
          unless lawyer
            render json: { error: "Advogado Não Encontrado - Verifique o OAB ID" }, status: :not_found
            return
          end

          @principal = lawyer.principal_lawyer || lawyer
        end
      end
    end
  end
end
