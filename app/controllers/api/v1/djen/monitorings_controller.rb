module Api
  module V1
    module Djen
      class MonitoringsController < ApplicationController
        include ApiAuthentication

        # ProcStudio holds only read API keys (one per environment). Any active
        # key may activate a watch; a read key may pause only its own hold, and
        # the watch stops when the last holder leaves — one consumer can never
        # silently pause another's intimações. An admin key pauses the watch.
        before_action :set_watch_target

        # POST /api/v1/djen/monitorings  { "oab": "PR_54159" }
        # Idempotent: re-activating an existing watch returns 200.
        def create
          retried = false
          begin
            monitoring = existing_monitoring || new_monitoring
            newly_created = monitoring.new_record?
            reactivating = !newly_created && !monitoring.active

            monitoring.active = true
            monitoring.source = params[:source].presence || monitoring.source || "procstudio"
            monitoring.save!
            monitoring.subscribe!(@api_key)
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
          monitoring = existing_monitoring
          unless monitoring
            render json: { error: "Advogado não monitorado no DJEN" }, status: :not_found
            return
          end

          render json: DjenMonitoringSerializer.new(monitoring).as_json, status: :ok
        end

        # DELETE /api/v1/djen/monitorings/:oab — pauses; history is kept.
        def destroy
          monitoring = existing_monitoring
          unless monitoring
            render json: { error: "Advogado não monitorado no DJEN" }, status: :not_found
            return
          end

          if @api_key.admin?
            monitoring.update!(active: false)
          elsif monitoring.holder_key_ids.include?(@api_key.id)
            monitoring.unsubscribe!(@api_key)
          else
            render json: { error: "Forbidden: esta API key não monitora este advogado" }, status: :forbidden
            return
          end

          render json: DjenMonitoringSerializer.new(monitoring).as_json, status: :ok
        end

        private

        # Accepts any of the lawyer's OABs (principal or supplementary) and
        # resolves to the principal, so one person never gets two watches.
        #
        # The scraped base is informative only: an OAB missing from it (scraper
        # behind or unreliable) is still watched, by the OAB itself. Only a
        # malformed OAB or an unknown UF is refused.
        def set_watch_target
          oab = params[:oab]
          unless oab.is_a?(String) && oab.present?
            render json: { error: "OAB ID obrigatório (ex: PR_54159)" }, status: :bad_request
            return
          end

          @oab = oab.strip.upcase
          lawyer = Lawyer.find_by(oab_id: @oab)
          @principal = lawyer.principal_lawyer || lawyer if lawyer
          return if @principal || valid_unscraped_oab?(@oab)

          render json: { error: "Advogado Não Encontrado - Verifique o OAB ID" }, status: :not_found
        end

        # A watch created while the OAB was missing from the base keeps being
        # the one used after the scraper catches up — a second, lawyer-based
        # watch would sweep and push the same OAB twice.
        def existing_monitoring
          DjenMonitoring.without_lawyer(@oab) || @principal&.djen_monitoring
        end

        def new_monitoring
          @principal ? DjenMonitoring.new(lawyer: @principal) : DjenMonitoring.new(oab_id: @oab)
        end

        def valid_unscraped_oab?(oab)
          match = oab.match(DjenMonitoring::OAB_FORMAT)
          match.present? && Api::V1::LawyersController::VALID_STATES.include?(match[:uf])
        end
      end
    end
  end
end
