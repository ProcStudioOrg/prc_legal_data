module Api
  module V1
    module Receita
      # Listagem de estabelecimentos da Receita para prospecção (FFD).
      # Cursor por cnpj crescente, limite 500. Defaults conservadores: ativas,
      # matriz, só naturezas de sociedade de advogados.
      class CompaniesController < ApplicationController
        include ApiAuthentication
        include UsageTracking

        MAX_LIMIT = 500
        DEFAULT_LIMIT = 100
        VALID_STATES = Api::V1::LawyersController::VALID_STATES

        def index
          uf = params[:uf].to_s.upcase
          return render json: { error: "Parâmetro uf é obrigatório" }, status: :bad_request if uf.blank?
          return render json: { error: "uf inválida. Válidas: #{VALID_STATES.join(', ')}" }, status: :bad_request unless VALID_STATES.include?(uf)

          limit = params[:limit].to_i
          limit = DEFAULT_LIMIT if limit <= 0
          limit = [ limit, MAX_LIMIT ].min

          scope = ::ReceitaCompany.from_dump.where(uf: uf)
          scope = apply_situacao(scope)
          scope = scope.matrizes unless params[:matriz].to_s == "false"
          scope = apply_natureza(scope)
          founded_since = parse_param(:founded_since) { |v| Date.iso8601(v) }
          updated_since = parse_param(:updated_since) { |v| Time.iso8601(v) }
          scope = scope.where("data_inicio_atividade >= ?", founded_since) if founded_since
          scope = scope.where("receita_companies.updated_at >= ?", updated_since) if updated_since
          scope = scope.where(society_id: nil).where.not(cnpj_root: ::ReceitaCompany.where.not(society_id: nil).select(:cnpj_root)) if params[:unmatched].to_s == "true"
          scope = scope.where(id: ::ReceitaPartner.linked.select(:receita_company_id)) if params[:known_lawyer].to_s == "true"
          scope = scope.where("cnpj > ?", params[:from_cnpj].to_s) if params[:from_cnpj].to_s.present?

          records = scope.order(:cnpj).limit(limit + 1).includes(receita_partners: :lawyer).to_a
          has_more = records.size > limit
          page = has_more ? records.first(limit) : records

          render json: {
            companies: ReceitaCompanySerializer.serialize_collection(page),
            meta: {
              returned: page.size,
              next_from_cnpj: has_more ? page.last.cnpj : nil,
              filters_applied: { uf: uf, limit: limit, situacao: params[:situacao].presence || "Ativa",
                                 matriz: params[:matriz].to_s != "false", natureza: natureza_applied,
                                 founded_since: params[:founded_since].presence&.to_s, updated_since: params[:updated_since].presence&.to_s,
                                 unmatched: params[:unmatched].to_s == "true", known_lawyer: params[:known_lawyer].to_s == "true" }
            }
          }, status: :ok
        rescue InvalidParam => e
          render json: { error: "Parâmetro de data inválido: #{e.message}" }, status: :bad_request
        end

        private

        class InvalidParam < StandardError; end

        # Só o parse de data vira 400; qualquer outro ArgumentError continua sendo erro de verdade.
        def parse_param(name)
          value = params[name].to_s
          return nil if value.blank?

          yield value
        rescue ArgumentError, Date::Error
          raise InvalidParam, "#{name} deve estar em formato ISO 8601"
        end

        def natureza_applied
          params[:natureza].to_s == "all" ? "all" : natureza_filter
        end

        def apply_situacao(scope)
          situacao = params[:situacao].to_s
          return scope.ativas if situacao.blank?
          return scope if situacao == "all"

          scope.where(situacao_cadastral: situacao)
        end

        def natureza_filter
          params[:natureza].to_s.presence&.split(",")&.map(&:strip) || ::ReceitaCompany::SOCIETY_NATURES
        end

        def apply_natureza(scope)
          return scope if params[:natureza].to_s == "all"

          scope.where(natureza_juridica: natureza_filter)
        end
      end
    end
  end
end
