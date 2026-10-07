module Api
  module V1
    class CnpjController < ApplicationController
      include ApiAuthentication
      include UsageTracking

      # GET /api/v1/cnpj/:cnpj — tabela local primeiro, API pública do OpenCNPJ na falta.
      def show
        result = ::Receita::CnpjLookup.call(params[:cnpj])

        case result.status
        when :found
          render json: ReceitaCompanySerializer.new(result.company).as_json, status: :ok
        when :invalid
          render json: { error: 'CNPJ inválido' }, status: :unprocessable_entity
        when :not_found
          render json: { error: 'CNPJ não encontrado na Receita' }, status: :not_found
        else
          response.headers['Retry-After'] = result.retry_after.to_s if result.retry_after
          render json: { error: 'Receita indisponível no momento', retry_after: result.retry_after }, status: :service_unavailable
        end
      end
    end
  end
end
