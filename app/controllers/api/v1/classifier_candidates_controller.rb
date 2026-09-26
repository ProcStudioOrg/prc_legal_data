module Api
  module V1
    # Explicit capability endpoint: older servers fail closed (404).
    class ClassifierCandidatesController < ApplicationController
      include ApiAuthentication
      include UsageTracking

      def index
        state = params[:state].to_s.upcase
        city = I18n.transliterate(params[:city].to_s).downcase.strip.gsub(/\s+/, " ")
        order = params[:order].to_s
        min = Integer(params[:min_oab].to_s, 10)
        max = Integer(params[:max_oab].to_s, 10)
        limit = Integer(params.fetch(:limit, "100").to_s, 10)
        unless LawyersController::VALID_STATES.include?(state) && city.present? && city.length <= 120 && %w[asc desc].include?(order) && min >= 0 && max >= min && max <= 2_147_483_647 && (1..100).cover?(limit)
          raise ArgumentError
        end
        filters = { state: state, city: city, min_oab: min, max_oab: max, order: order }
        # Pick the first matching registration per person BEFORE pagination.
        # Principal OAB in another UF must never affect local numeric ordering.
        numeric = "CAST(reg.oab_number AS BIGINT)"
        direction = order == "asc" ? "ASC" : "DESC"
        city_sql = "regexp_replace(trim(translate(lower(reg.city), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')), '\\s+', ' ', 'g')"
        sql = Lawyer.sanitize_sql_array([ <<~SQL, state, city, min, max ])
          SELECT reg.*, COALESCE(reg.principal_lawyer_id, reg.id) AS canonical_id,
                 #{numeric} AS matched_number,
                 ROW_NUMBER() OVER (PARTITION BY COALESCE(reg.principal_lawyer_id, reg.id) ORDER BY #{numeric} #{direction}, reg.id #{direction}) AS person_rank
          FROM lawyers reg JOIN lawyers principal ON principal.id = COALESCE(reg.principal_lawyer_id, reg.id)
          WHERE reg.state = ? AND #{city_sql} = ?
            AND reg.oab_number ~ '^[0-9]{1,10}$' AND #{numeric} BETWEEN ? AND ?
            AND lower(COALESCE(reg.situation, '')) NOT SIMILAR TO '%%(cancelado|falecido)%%'
            AND lower(COALESCE(principal.situation, '')) NOT SIMILAR TO '%%(cancelado|falecido)%%'
            AND NOT EXISTS (SELECT 1 FROM lawyers customer WHERE COALESCE(customer.principal_lawyer_id, customer.id) = principal.id AND customer.is_procstudio = true)
        SQL
        relation = Lawyer.from("(#{sql}) lawyers").where(person_rank: 1)
        if params[:cursor].present?
          cursor = JSON.parse(Base64.urlsafe_decode64(params[:cursor]))
          raise ArgumentError unless cursor.is_a?(Hash) && cursor["filters"] == filters.stringify_keys && cursor["number"].is_a?(Integer) && cursor["id"].is_a?(Integer)
          comparison = order == "asc" ? ">" : "<"
          relation = relation.where("(matched_number, id) #{comparison} (?, ?)", cursor["number"], cursor["id"])
        end
        records = relation.order(Arel.sql("matched_number #{direction}, id #{direction}")).limit(limit + 1).to_a
        page = records.first(limit)
        ids = page.map { |r| r["canonical_id"] }
        principals = Lawyer.where(id: ids).index_by(&:id)
        aliases = Lawyer.where("id IN (?) OR principal_lawyer_id IN (?)", ids, ids).group_by { |l| l.principal_lawyer_id || l.id }
        rows = page.map do |r|
          p = principals.fetch(r["canonical_id"])
          { oab_id: p.oab_id, matched_oab_id: r.oab_id, matched_oab_number: r["matched_number"],
            full_name: p.full_name, city: r.city, state: r.state,
            canonical_city: p.city, canonical_state: p.state,
            registrations: aliases.fetch(p.id).map(&:oab_id) }
        end
        next_cursor = if records.length > limit
          Base64.urlsafe_encode64({ filters: filters, number: page.last["matched_number"], id: page.last.id }.to_json)
        end
        render json: { contract: "classifier-candidates-v1", filters: filters, lawyers: rows, next_cursor: next_cursor }
      rescue ArgumentError, TypeError, JSON::ParserError
        render json: { error: "Seleção inválida: informe UF, cidade, faixa numérica inclusiva e ordem asc/desc." }, status: :bad_request
      end
    end
  end
end
