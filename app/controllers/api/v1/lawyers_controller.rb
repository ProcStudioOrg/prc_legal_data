# app/controllers/api/v1/lawyers_controller.rb
module Api
  module V1
    class LawyersController < ApplicationController
      include ApiAuthentication

      before_action :authorize_write!, only: [ :create_lawyer, :update_lawyer, :update_crm ]
      before_action :set_lawyer, only: [ :_debug, :update_lawyer, :update_crm, :show_crm ]

      # --- Batch fetch for scraper ---
      def index
        state = params[:state]&.upcase

        unless state.present?
          render json: { error: "Estado obrigatório" }, status: :bad_request
          return
        end

        unless VALID_STATES.include?(state)
          render json: { error: "Estado inválido. Estados válidos: #{VALID_STATES.join(', ')}" }, status: :bad_request
          return
        end

        limit = [[params.fetch(:limit, 50).to_i, 1].max, 100].min
        from_oab = params[:from_oab]

        lawyers = Lawyer
          .where(state: state)
          .where("situation ILIKE ?", "%regular%")
          .where("is_procstudio IS NULL OR is_procstudio = false")

        if from_oab.present?
          unless from_oab.match?(/\A\d+\z/)
            render json: { error: "from_oab deve ser numérico" }, status: :bad_request
            return
          end
          lawyers = lawyers.where("CAST(oab_number AS INTEGER) < ?", from_oab.to_i)
        end

        if params[:scraped] == "false"
          lawyers = lawyers.where("crm_data->>'scraped' IS NULL OR crm_data->>'scraped' != 'true'")
        end

        # Fetch limit+1 to determine if there's a next page without an extra COUNT query
        lawyers = lawyers
          .order(Arel.sql("CAST(oab_number AS INTEGER) DESC"))
          .limit(limit + 1)
          .includes(:supplementary_lawyers, :principal_lawyer, lawyer_societies: { society: { lawyer_societies: :lawyer } })

        all_records = lawyers.to_a
        has_more = all_records.length > limit
        page_records = has_more ? all_records.first(limit) : all_records

        serialized = page_records.map { |l| ScraperLawyerSerializer.new(l).as_json }

        last_oab = serialized.any? ? serialized.last[:oab_number] : nil
        next_from_oab = has_more ? last_oab : nil

        render json: {
          lawyers: serialized,
          meta: {
            returned: serialized.length,
            state: state,
            from_oab: from_oab,
            next_from_oab: next_from_oab
          }
        }, status: :ok
      rescue => e
        Rails.logger.error("Error in lawyers#index: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
        render json: {
          error: "Erro interno ao listar advogados",
          error_type: e.class.name,
          request_id: request.request_id
        }, status: :internal_server_error
      end

      # --- Create lawyer action ---
      def create_lawyer
        begin
          # 1. Validate the required parameters
          create_params = lawyer_create_params

          unless create_params[:oab_number].present? && create_params[:state].present? && create_params[:oab_id].present?
            render json: { error: "Número OAB, Estado e OAB ID são obrigatórios" }, status: :bad_request
            return
          end

          # 2. Get the oab_id from the request params
          # State and oab_number are used only for validation purposes
          state = create_params[:state].upcase
          oab_number = create_params[:oab_number].strip
          oab_id = create_params[:oab_id]

          # 3. Use a transaction to prevent race conditions
          lawyer = nil
          Lawyer.transaction do
            # Check if a lawyer with this OAB ID already exists (case-insensitive)
            existing_lawyer = Lawyer.where("UPPER(oab_id) = ?", oab_id.upcase).first

            if existing_lawyer
              render json: {
                error: "Advogado com OAB #{oab_id} já cadastrado",
                lawyer_id: existing_lawyer.id
              }, status: :conflict
              return
            end

            # 4. Build the lawyer object with all parameters
            @lawyer = Lawyer.new(create_params)
            @lawyer.oab_id = oab_id

            # 5. Save the lawyer
            unless @lawyer.save
              render json: {
                error: "Erro ao criar advogado",
                details: @lawyer.errors.full_messages
              }, status: :unprocessable_entity
              return
            end

            lawyer = @lawyer
          end

          # Only reached if transaction was successful
          render json: {
            message: "Advogado criado com sucesso",
            lawyer: lawyer.as_json
          }, status: :created
        rescue ActionDispatch::Http::Parameters::ParseError => e
          Rails.logger.error("JSON parse error in create_lawyer: #{e.message}")
          render json: {
            error: "Erro ao processar parâmetros JSON",
            message: "Verifique se o formato JSON está correto",
            error_type: e.class.name,
            request_id: request.request_id
          }, status: :bad_request
        rescue => e
          oab_id_text = defined?(oab_id) ? oab_id : "unknown"
          Rails.logger.error("Error creating lawyer with OAB #{oab_id_text}: #{e.message}")
          error_details = Rails.env.production? ? nil : { message: e.message, backtrace: e.backtrace&.first(5) }
          Rails.logger.error("Error creating lawyer with OAB #{oab_id_text}: #{e.message}\n#{e.backtrace&.join("\n")}")
          render json: {
            error: "Erro interno ao criar advogado",
            error_type: e.class.name,
            details: error_details,
            request_id: request.request_id
          }, status: :internal_server_error
        end
      end

      # --- MODIFIED show_by_oab action ---
      def show_by_oab
        oab = params[:oab]

        # 1. Validate presence of OAB parameter
        unless oab.present?
          render json: { error: "Número OAB obrigatório" }, status: :bad_request
          return
        end

        # 2. Find the initially requested lawyer record with eager loading
        found_lawyer = Lawyer.includes(:principal_lawyer, :supplementary_lawyers, :lawyer_societies, :societies).find_by(oab_id: oab)

        # 3. Handle case where no lawyer is found for the given OAB ID
        unless found_lawyer
          render json: { error: "Advogado Não Encontrado - Verifique o OAB ID" }, status: :not_found
          return
        end

        # 4. Determine the principal lawyer and associated supplementaries
        principal_lawyer = nil
        supplementary_lawyers = []

        if found_lawyer.principal_lawyer_id.present?
          # The found lawyer is supplementary
          principal_lawyer = found_lawyer.principal_lawyer

          # Data integrity check: Ensure the principal record actually exists
          unless principal_lawyer
            error_message = "Data Integrity Issue: Supplementary Lawyer ID #{found_lawyer.id} has principal_lawyer_id #{found_lawyer.principal_lawyer_id}, but the principal record was not found."
            Rails.logger.error(error_message)
            render json: {
              error: "Erro interno: Registro principal associado não encontrado.",
              error_details: error_message,
              request_id: request.request_id
            }, status: :internal_server_error
            return
          end

          # Fetch all supplementaries related to this principal (with societies)
          supplementary_lawyers = principal_lawyer.supplementary_lawyers.includes(:lawyer_societies, :societies)
        else
          # The found lawyer is the principal
          principal_lawyer = found_lawyer
          supplementary_lawyers = principal_lawyer.supplementary_lawyers.includes(:lawyer_societies, :societies)
        end

        # 5. Perform status check on the PRINCIPAL lawyer's record
        status_check = verify_lawyer_status(principal_lawyer)
        unless status_check[:valid]
          render json: { error: "Status Inválido (Principal): #{status_check[:message]}" }, status: :unprocessable_entity
          return
        end

        # 6. Prepare the response structure using serializers
        principal_response = LawyerSerializer.new(principal_lawyer, include_societies: true).as_json

        # Format supplementary lawyer data using serializers
        supplementaries_response = supplementary_lawyers.map do |supp|
          LawyerSerializer.new(supp, include_societies: true).as_json
        end

        # Combine into the final response
        final_response = {
          principal: principal_response,
          supplementaries: supplementaries_response
        }

        # 7. Render the final JSON response
        render json: final_response, status: :ok

      rescue ActiveRecord::RecordNotFound => e
         Rails.logger.error("RecordNotFound in show_by_oab: #{e.message}")
         error_details = Rails.env.production? ? nil : { message: e.message, backtrace: e.backtrace&.first(5) }
         render json: {
           error: "Erro interno ao buscar advogado",
           error_type: e.class.name,
           details: error_details,
           request_id: request.request_id
         }, status: :internal_server_error
      rescue => e
         Rails.logger.error("Error in show_by_oab for OAB #{oab}: #{e.message}\n#{e.backtrace.join("\n")}")
         error_details = Rails.env.production? ? nil : { message: e.message, backtrace: e.backtrace&.first(5) }
         render json: {
           error: "Ocorreu um erro inesperado ao processar a solicitação.",
           error_type: e.class.name,
           details: error_details,
           request_id: request.request_id
         }, status: :internal_server_error
      end

      # --- Show CRM data for a single lawyer ---
      def show_crm
        unless @lawyer
          render json: { error: "Advogado Não Encontrado - Verifique o OAB ID" }, status: :not_found
          return
        end

        # Re-fetch with eager loading so the serializer doesn't N+1.
        base_relation = Lawyer.includes(
          :supplementary_lawyers,
          :principal_lawyer,
          lawyer_societies: { society: { lawyer_societies: { lawyer: :supplementary_lawyers } } }
        )
        loaded = base_relation.find_by(id: @lawyer.id)

        principal_lawyer = loaded.principal_lawyer_id.present? ? loaded.principal_lawyer : loaded
        # When walking principal -> reload principal with the same eager set so partner societies are loaded.
        if loaded.principal_lawyer_id.present?
          principal_lawyer = base_relation.find_by(id: loaded.principal_lawyer_id)
        end

        unless principal_lawyer
          Rails.logger.error("Data Integrity Issue: supplementary lawyer #{loaded.id} has principal_lawyer_id #{loaded.principal_lawyer_id} but principal not found")
          render json: { error: "Erro interno: Registro principal associado não encontrado.", request_id: request.request_id }, status: :internal_server_error
          return
        end

        status_check = verify_lawyer_status(principal_lawyer)
        unless status_check[:valid]
          render json: { error: "Status Inválido (Principal): #{status_check[:message]}" }, status: :unprocessable_entity
          return
        end

        render json: { principal: LawyerCrmSerializer.new(principal_lawyer).as_json }, status: :ok
      rescue => e
        Rails.logger.error("Error in show_crm for OAB #{params[:oab]}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
        error_details = Rails.env.production? ? nil : { message: e.message, backtrace: e.backtrace&.first(5) }
        render json: {
          error: "Erro interno ao buscar advogado",
          error_type: e.class.name,
          details: error_details,
          request_id: request.request_id
        }, status: :internal_server_error
      end

      # --- List lawyers with CRM data ---
      def crm_index
        state = params[:state]&.upcase

        if state.present? && !VALID_STATES.include?(state)
          render json: { error: "Estado inválido. Estados válidos: #{VALID_STATES.join(', ')}" }, status: :bad_request
          return
        end

        min_lead_score = params[:min_lead_score]
        if min_lead_score.present? && !min_lead_score.to_s.match?(/\A\d+\z/)
          render json: { error: "min_lead_score deve ser numérico" }, status: :bad_request
          return
        end

        limit = [[params.fetch(:limit, 50).to_i, 1].max, 100].min

        lawyers = Lawyer
          .where("is_procstudio IS NULL OR is_procstudio = false")
          .where(principal_lawyer_id: nil)

        lawyers = lawyers.where(state: state) if state.present?

        if params[:scraped] == "true"
          lawyers = lawyers.where("crm_data->'scraper'->>'scraped' = 'true'")
        end

        if params[:stage].present?
          lawyers = lawyers.where("crm_data->'outreach'->>'stage' = ?", params[:stage])
        end

        if params[:has_instagram] == "true"
          lawyers = lawyers.where("instagram IS NOT NULL AND instagram != ''")
        end

        if params[:has_website] == "true"
          lawyers = lawyers.where("website IS NOT NULL AND website != ''")
        end

        if min_lead_score.present?
          lawyers = lawyers.where(
            "crm_data->'scraper'->>'lead_score' ~ '^\\d+$' AND (crm_data->'scraper'->>'lead_score')::int >= ?",
            min_lead_score.to_i
          )
        end

        lawyers = lawyers.order(oab_id: :desc).limit(limit + 1)

        records = lawyers.to_a
        has_more = records.length > limit
        page = has_more ? records.first(limit) : records

        serialized = page.map { |l| LawyerCrmListSerializer.new(l).as_json }
        next_from_oab = has_more ? page.last.oab_id : nil

        render json: {
          lawyers: serialized,
          meta: {
            returned: serialized.length,
            next_from_oab: next_from_oab,
            filters_applied: filters_applied_summary
          }
        }, status: :ok
      rescue => e
        Rails.logger.error("Error in crm_index: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
        render json: {
          error: "Erro interno ao listar advogados (CRM)",
          error_type: e.class.name,
          request_id: request.request_id
        }, status: :internal_server_error
      end

      VALID_STATES = %w[
        AC AL AP AM BA CE DF ES GO MA
        MT MS MG PA PB PR PE PI RJ RN
        RS RO RR SC SP SE TO
      ].freeze

      # --- Buscar última OAB por estado (SQL optimized + cached) ---
      def last_oab_by_state
        state = params[:state]&.upcase

        unless state.present?
          render json: { error: "Estado obrigatório" }, status: :bad_request
          return
        end

        unless VALID_STATES.include?(state)
          render json: {
            error: "Estado inválido. Estados válidos: #{VALID_STATES.join(', ')}"
          }, status: :bad_request
          return
        end

        result = Rails.cache.fetch("last_oab_by_state:#{state}", expires_in: 6.hours) do
          total = Lawyer.where("oab_id LIKE ?", "#{state}_%").count

          if total == 0
            { state: state, message: "Nenhum advogado encontrado para o estado #{state}", last_oab: nil, total_lawyers: 0 }
          else
            lawyer = Lawyer
              .where("oab_id LIKE ?", "#{state}_%")
              .order(Arel.sql("CAST(SPLIT_PART(oab_id, '_', 2) AS INTEGER) DESC"))
              .limit(1)
              .first

            {
              state: state,
              last_oab: lawyer.oab_id,
              oab_number: lawyer.oab_number,
              lawyer_name: lawyer.full_name,
              city: lawyer.city,
              situation: lawyer.situation,
              total_lawyers: total,
              updated_at: lawyer.updated_at
            }
          end
        end

        render json: result, status: :ok
      end

      # --- Update lawyer action ---
      def update_lawyer
        oab = params[:oab]
        unless oab&.match?(/^[A-Z]{2}_\d+$/)
          render json: { error: "Formato OAB inválido. Use: ESTADO_NUMERO (ex: PR_115685)" }, status: :bad_request
          return
        end
        unless @lawyer
          render json: { error: "Advogado não encontrado" }, status: :not_found
          return
        end

        # Get the update parameters from the request
        update_params = lawyer_update_params

        if update_params.empty?
          render json: { error: "Nenhum parâmetro de atualização fornecido" }, status: :bad_request
          return
        end

        begin
          if @lawyer.update(update_params)
            render json: {
              message: "Advogado atualizado com sucesso",
              lawyer: @lawyer.as_json
            }, status: :ok
          else
            render json: {
              error: "Erro ao atualizar advogado",
              details: @lawyer.errors.full_messages
            }, status: :unprocessable_entity
          end
        rescue => e
          Rails.logger.error("Error updating lawyer #{@lawyer.oab_id}: #{e.message}")
          error_details = Rails.env.production? ? nil : { message: e.message, backtrace: e.backtrace&.first(5) }
          Rails.logger.error("Error updating lawyer #{@lawyer.oab_id}: #{e.message}\n#{e.backtrace&.join("\n")}")
          render json: {
            error: "Erro interno ao atualizar advogado",
            error_type: e.class.name,
            details: error_details,
            request_id: request.request_id
          }, status: :internal_server_error
        end
      end

      # --- Update CRM data action ---
      # This endpoint allows updating/adding specific fields to the crm_data JSON
      # It merges new data with existing data, allowing partial updates
      def update_crm
        unless @lawyer
          render json: { error: "Advogado não encontrado" }, status: :not_found
          return
        end

        crm_params = params.permit(
          :researched, :last_research_date, :trial_active,
          :tried_procstudio, :mail_marketing, :contacted,
          :contacted_by, :contacted_when, :contact_notes,
          mail_marketing_origin: []
        ).to_h

        # Free-form deep-permit for AI-driven sub-hashes.
        %i[scraper outreach signals].each do |key|
          raw = params[key]
          next if raw.blank?
          crm_params[key.to_s] = deep_permit_hash(raw)
        end

        if crm_params.empty?
          render json: { error: "Nenhum parâmetro CRM fornecido" }, status: :bad_request
          return
        end

        begin
          current_crm = @lawyer.crm_data || {}
          new_crm = current_crm.deep_merge(crm_params.compact)

          if @lawyer.update(crm_data: new_crm)
            render json: {
              message: "Dados CRM atualizados com sucesso",
              oab_id: @lawyer.oab_id,
              crm_data: @lawyer.crm_data
            }, status: :ok
          else
            render json: {
              error: "Erro ao atualizar dados CRM",
              details: @lawyer.errors.full_messages
            }, status: :unprocessable_entity
          end
        rescue => e
          Rails.logger.error("Error updating CRM for lawyer #{@lawyer.oab_id}: #{e.message}")
          error_details = Rails.env.production? ? nil : { message: e.message, backtrace: e.backtrace&.first(5) }
          render json: {
            error: "Erro interno ao atualizar dados CRM",
            error_type: e.class.name,
            details: error_details,
            request_id: request.request_id
          }, status: :internal_server_error
        end
      end

      # --- Existing _debug action ---
      def _debug
        if @lawyer
          status_check = verify_lawyer_status(@lawyer)

          profile_picture_url = format_image_url(@lawyer.profile_picture, :profile)
          cna_picture_url = format_image_url(@lawyer.cna_picture, :cna)

          regular_attrs = {
            situation: @lawyer.situation,
            full_name: @lawyer.full_name,
            oab_number: @lawyer.oab_number,
            city: @lawyer.city,
            state: @lawyer.state,
            address: @lawyer.address,
            original_address: @lawyer.original_address,
            zip_code: @lawyer.zip_code,
            phone_number_1: @lawyer.phone_number_1,
            phone_number_2: @lawyer.phone_number_2,
            phone_1_has_whatsapp: @lawyer.phone_1_has_whatsapp,
            phone_2_has_whatsapp: @lawyer.phone_2_has_whatsapp,
            supplementary: @lawyer.suplementary,
            profession: @lawyer.profession,
            profile_picture: profile_picture_url,
            principal_lawyer_id: @lawyer.principal_lawyer_id
          }

          debug_attrs = {
            folder_id: @lawyer.folder_id,
            cna_picture: cna_picture_url,
            is_procstudio: @lawyer.is_procstudio,
            has_society: @lawyer.lawyer_societies.exists?,
            societies: @lawyer.societies.pluck(:id, :name).map { |id, name| {id: id, name: name} },
            specialty: @lawyer.specialty,
            bio: @lawyer.bio,
            email: @lawyer.email,
            instagram: @lawyer.instagram,
            website: @lawyer.website,
            created_at: @lawyer.created_at,
            updated_at: @lawyer.updated_at
          }

          request_info = {
            requester: {
              user_id: @current_user&.id,
              api_key_id: @api_key&.id
            },
            ip: request.ip,
            user_agent: request.user_agent,
            request_time: @request_start_time,
            response_time: Time.now,
            duration_ms: ((Time.now - @request_start_time) * 1000).round(2)
          }

          render json: {
            status_validation: status_check,
            regular_view: regular_attrs,
            debug_info: debug_attrs,
            request_context: request_info
          }
        else
          render json: { error: "Lawyer not found" }, status: :not_found
        end
      end

      # --- Private methods ---
      private

      def format_image_url(image_name, _type = nil)
        return nil unless image_name.present?

        bucket = Rails.application.config.s3[:profile_pictures_bucket]
        "https://#{bucket}.s3.amazonaws.com/#{image_name}"
      end

      def verify_lawyer_status(lawyer)
        situation = lawyer.situation.to_s.downcase

        if situation.include?("cancelado")
          {
            valid: false,
            message: "Advogado consta como Cancelado no banco de dados",
            code: "cancelled_registration"
          }
        elsif situation.include?("falecido")
          {
            valid: false,
            message: "Advogado consta como Falecido no banco de dados",
            code: "deceased"
          }
        else
          {
            valid: true,
            message: "Situação regular",
            code: "active"
          }
        end
      end

      def filters_applied_summary
        {
          state: params[:state]&.upcase,
          scraped: params[:scraped],
          stage: params[:stage],
          min_lead_score: params[:min_lead_score],
          has_instagram: params[:has_instagram],
          has_website: params[:has_website],
          from_oab: params[:from_oab]
        }.compact
      end

      def set_lawyer
        oab = params[:oab]
        @lawyer = Lawyer.find_by(oab_id: oab) if oab.present?
      end

      # Recursively converts ActionController::Parameters (and nested hashes/arrays)
      # into a plain Ruby hash with stringified keys. Used to allow free-form
      # sub-hashes under the :scraper, :outreach, and :signals namespaces without
      # opening up arbitrary root-level params — the whitelist boundary is the
      # explicit %i[scraper outreach signals] list in update_crm.
      def deep_permit_hash(value)
        case value
        when ActionController::Parameters
          value.to_unsafe_h.transform_values { |v| deep_permit_hash(v) }.deep_stringify_keys
        when Hash
          value.transform_values { |v| deep_permit_hash(v) }.deep_stringify_keys
        when Array
          value.map { |v| deep_permit_hash(v) }
        else
          value
        end
      end

      # Strong parameters for lawyer updates
      def lawyer_update_params
        params.permit(
          :full_name, :oab_number, :city, :state, :address, :original_address,
          :zip_code, :phone_number_1, :phone_number_2, :phone_1_has_whatsapp, :phone_2_has_whatsapp,
          :profession, :situation, :suplementary, :is_procstudio,
          :specialty, :bio, :email, :instagram, :website, :profile_picture, :cna_picture,
          :social_name, :has_society, :cna_link, :detail_url, :zip_address, :society_basic_details
        )
      end

      # Strong parameters for lawyer creation
      def lawyer_create_params
        params.permit(
          :full_name, :oab_number, :oab_id, :city, :state, :address, :original_address,
          :zip_code, :phone_number_1, :phone_number_2, :phone_1_has_whatsapp, :phone_2_has_whatsapp,
          :profession, :situation, :suplementary, :is_procstudio,
          :specialty, :bio, :email, :instagram, :website, :profile_picture, :cna_picture,
          :principal_lawyer_id, :folder_id, :social_name, :has_society, :cna_link, :detail_url, :zip_address, :society_basic_details
        )
      end
    end
  end
end
