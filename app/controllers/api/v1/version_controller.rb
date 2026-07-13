module Api
  module V1
    # Público (sem X-API-KEY): o frontend e o deploy consultam sem credencial.
    class VersionController < ApplicationController
      def show
        render json: AppVersion.to_h, status: :ok
      end
    end
  end
end
