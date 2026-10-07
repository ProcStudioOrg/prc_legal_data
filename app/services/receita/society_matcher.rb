# app/services/receita/society_matcher.rb
# frozen_string_literal: true

module Receita
  # Casa Society (OAB) com ReceitaCompany, 100% offline, por UF.
  #
  # Regras herdadas do PLANO-CNPJA.md §2 (cada uma custou um caso real):
  #   - nome igual NÃO basta (LEON): precisa de sócio batendo;
  #   - nome igual não é obrigatório (FIGUEIRERO): 2+ sócios batendo bastam;
  #   - autoridade = sobreposição de nome de sócio; nome da firma é pista;
  #   - contagem de sócios não é critério (associado não entra no QSA);
  #   - matriz e filial são a MESMA raiz de CNPJ: escolhe a matriz ativa;
  #   - raízes diferentes com sócio comum: ambiguous, humano decide.
  #
  # Só verified grava societies.cnpj. Nunca promove ambiguous.
  class SocietyMatcher
    VERIFIED = "verified"
    AMBIGUOUS = "ambiguous"
    UNMATCHED = "unmatched"
    MIN_PARTNERS_WITHOUT_NAME = 2

    Candidate = Struct.new(:id, :cnpj, :root, :name, :matriz, :ativa, :partners, keyword_init: true)

    def initialize(state:, release:, dry_run: false, logger: Rails.logger)
      @state = state.to_s.upcase
      @release = release
      @dry_run = dry_run
      @logger = logger
      @stats = Hash.new(0)
    end

    def call
      load_companies
      taken_cnpjs = Society.where.not(cnpj: nil).pluck(:cnpj).to_set

      Society.where(state: @state).includes(:lawyers).find_each do |society|
        @stats[:societies] += 1
        lawyer_names = society.lawyers.each_with_object({}) do |l, h|
          key = NameNormalizer.call(l.full_name)
          next if key.empty?

          # Dois advogados da mesma sociedade com o mesmo nome normalizado: não dá
          # para saber qual é qual, então nenhum recebe o vínculo.
          h[key] = h.key?(key) ? nil : l.id
        end
        next @stats[:no_lawyers] += 1 if lawyer_names.empty?

        if society.cnpja_match_confidence == VERIFIED && society.cnpj.present?
          @stats[:already_verified] += 1
          touch_synced(society)
          attach_verified_company(society, lawyer_names)
          next
        end

        decide(society, lawyer_names, taken_cnpjs)
      end

      @logger.info("Receita::SocietyMatcher #{@state}: #{@stats.map { |k, v| "#{k}=#{v}" }.join(' ')}")
      @stats
    end

    private

    # Índices em memória da UF: por nome da firma e por nome de sócio PF.
    def load_companies
      @by_id = {}
      @by_name = Hash.new { |h, k| h[k] = [] }
      @by_partner = Hash.new { |h, k| h[k] = [] }

      ReceitaCompany.where(uf: @state).from_dump
                    .pluck(:id, :cnpj, :cnpj_root, :name_normalized, :matriz, :situacao_cadastral)
                    .each do |id, cnpj, root, name, matriz, situacao|
        c = Candidate.new(id: id, cnpj: cnpj, root: root, name: name, matriz: matriz, ativa: situacao == "Ativa", partners: {})
        @by_id[id] = c
        @by_name[name] << c if name.present?
      end

      ReceitaPartner.pessoa_fisica
                    .where(receita_company_id: @by_id.keys, last_seen_release: @release)
                    .pluck(:receita_company_id, :name_normalized, :id)
                    .each do |company_id, name, partner_id|
        next if name.blank?

        c = @by_id[company_id]
        c.partners[name] = partner_id
        @by_partner[name] << c
      end
    end

    def decide(society, lawyer_names, taken_cnpjs)
      society_name = NameNormalizer.call(society.name)
      candidates = @by_name[society_name].to_set
      lawyer_names.each_key { |n| candidates.merge(@by_partner[n]) }

      strong = candidates.filter_map do |c|
        hits = c.partners.keys & lawyer_names.keys
        next if hits.empty?
        next unless c.name == society_name || hits.size >= MIN_PARTNERS_WITHOUT_NAME

        [ c, hits ]
      end

      if strong.empty?
        @stats[:unmatched] += 1
        return
      end

      roots = strong.map { |c, _| c.root }.uniq
      if roots.size > 1
        mark_ambiguous(society, strong.map(&:first))
        return
      end

      pick, hits = strong.min_by { |c, _| [ c.matriz ? 0 : 1, c.ativa ? 0 : 1, c.cnpj ] }
      if taken_cnpjs.include?(pick.cnpj) && Society.where(cnpj: pick.cnpj).pick(:id) != society.id
        @stats[:ambiguous_cnpj_taken] += 1
        mark_ambiguous(society, [ pick ])
        return
      end

      taken_cnpjs << pick.cnpj
      @stats[:verified] += 1
      @stats[pick.name == society_name ? :verified_exact_name : :verified_partners_only] += 1
      write_verified(society, pick, hits, lawyer_names)
    end

    def write_verified(society, pick, hits, lawyer_names)
      return if @dry_run

      now = Time.current
      ActiveRecord::Base.transaction do
        society.update_columns(cnpj: pick.cnpj, cnpja_match_confidence: VERIFIED, cnpja_synced_at: now)
        ReceitaCompany.where(id: pick.id).update_all(society_id: society.id, match_confidence: VERIFIED, matched_at: now)
        link_partners(pick.partners.slice(*hits), lawyer_names)
      end
    end

    # Sociedade já verified (ou promovida por humano): anexa a company do dump
    # que ainda não tem dona e vincula os sócios que batem com os advogados.
    def attach_verified_company(society, lawyer_names)
      company = ReceitaCompany.find_by(cnpj: society.cnpj)
      return if company.nil? || (company.society_id && company.society_id != society.id)

      @stats[:verified_attached] += 1
      return if @dry_run

      ActiveRecord::Base.transaction do
        ReceitaCompany.where(id: company.id).update_all(society_id: society.id, match_confidence: VERIFIED, matched_at: Time.current)
        partners = ReceitaPartner.pessoa_fisica.where(receita_company_id: company.id, name_normalized: lawyer_names.keys)
                                 .pluck(:name_normalized, :id).to_h
        link_partners(partners, lawyer_names)
      end
    end

    # partners: nome normalizado => id do ReceitaPartner (já restrito aos hits).
    def link_partners(partners, lawyer_names)
      partners.each do |name, partner_id|
        lawyer_id = lawyer_names[name]
        next if lawyer_id.nil?

        ReceitaPartner.where(id: partner_id).update_all(lawyer_id: lawyer_id)
      end
    end

    def mark_ambiguous(society, companies)
      @stats[:ambiguous] += 1
      return if @dry_run

      now = Time.current
      society.update_columns(cnpja_match_confidence: AMBIGUOUS, cnpja_synced_at: now)
      ReceitaCompany.where(id: companies.map(&:id), society_id: nil).update_all(match_confidence: AMBIGUOUS, matched_at: now)
    end

    def touch_synced(society)
      return if @dry_run

      society.update_columns(cnpja_synced_at: Time.current)
    end
  end
end
