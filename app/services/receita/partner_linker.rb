# frozen_string_literal: true

module Receita
  # Liga sócio PF (ainda sem lawyer_id) ao advogado PRINCIPAL da mesma UF cujo
  # nome normalizado é único. Homônimo na UF => sem vínculo (melhor sem do que
  # errado). Complementa o SocietyMatcher para firmas que NÃO são sociedade OAB
  # nossa (prospects), onde não há sociedade para dar autoridade.
  class PartnerLinker
    def initialize(state:, release:, dry_run: false, logger: Rails.logger)
      @state = state.to_s.upcase
      @release = release
      @dry_run = dry_run
      @logger = logger
      @stats = Hash.new(0)
    end

    def call
      index = lawyer_index

      ReceitaPartner.pessoa_fisica.unlinked
                    .joins(:receita_company)
                    .where(receita_companies: { uf: @state }, last_seen_release: @release)
                    .where.not(name_normalized: [ nil, "" ])
                    .in_batches(of: 5000) do |batch|
        updates = Hash.new { |h, k| h[k] = [] }
        batch.pluck(:id, :name_normalized).each do |partner_id, name|
          @stats[:candidates] += 1
          ids = index[name]
          if ids.nil?
            @stats[:no_lawyer] += 1
          elsif ids.size > 1
            @stats[:homonym_skipped] += 1
          else
            updates[ids.first] << partner_id
          end
        end
        next if @dry_run # dry_run não grava nem conta :linked

        updates.each { |lawyer_id, partner_ids| ReceitaPartner.where(id: partner_ids, lawyer_id: nil).update_all(lawyer_id: lawyer_id) }
        @stats[:linked] += updates.values.sum(&:size)
      end

      @logger.info("Receita::PartnerLinker #{@state}: #{@stats.map { |k, v| "#{k}=#{v}" }.join(' ')}")
      @stats
    end

    private

    # nome normalizado -> [ids de advogado principal] na UF
    def lawyer_index
      index = {}
      Lawyer.where(state: @state, principal_lawyer_id: nil).pluck(:id, :full_name).each do |id, full_name|
        key = NameNormalizer.call(full_name)
        (index[key] ||= []) << id unless key.empty?
      end
      index
    end
  end
end
