module Djen
  # The DJEN keeps a national registry of lawyers: `advogado.id` is the same
  # for one lawyer in every tribunal. There is no lookup endpoint — the id is
  # learned from `destinatarioadvogados[]` inside comunicação responses.
  #
  # Each lawyer ROW (principal and each supplementary) learns its own id, so we
  # can observe whether supplementary OABs resolve to the same national id.
  class AdvogadoIdLearner
    def initialize(lawyer, numero_oab:, uf_oab:)
      @lawyer = lawyer
      @numero_oab = numero_oab.to_s
      @uf_oab = uf_oab.to_s.upcase
    end

    # Returns :learned, :confirmed, :mismatch or :not_found for one DJEN item.
    def call(item)
      djen_id = extract_id(item)
      return :not_found if djen_id.nil?

      if @lawyer.djen_advogado_id.nil?
        @lawyer.update_column(:djen_advogado_id, djen_id)
        Rails.logger.info("Djen: learned advogado_id=#{djen_id} for #{@lawyer.oab_id}")
        :learned
      elsif @lawyer.djen_advogado_id == djen_id
        :confirmed
      else
        Rails.logger.warn(
          "Djen: ADVOGADO ID MISMATCH for #{@lawyer.oab_id} — " \
          "known=#{@lawyer.djen_advogado_id} got=#{djen_id} " \
          "(comunicacao #{item['id']}) — possible homonym or registry error"
        )
        :mismatch
      end
    end

    private

    def extract_id(item)
      (item["destinatarioadvogados"] || []).each do |da|
        adv = da["advogado"] || {}
        return adv["id"] if adv["numero_oab"].to_s == @numero_oab && adv["uf_oab"].to_s.upcase == @uf_oab
      end
      nil
    end
  end
end
