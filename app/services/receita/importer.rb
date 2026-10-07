# frozen_string_literal: true

module Receita
  # Importa um NDJSON do OpenCNPJ em receita_companies/receita_partners.
  #
  # Idempotente por (cnpj) e (empresa, nome normalizado, documento): rodar a
  # mesma release duas vezes não muda nada. Em release nova, a empresa é
  # sobrescrita (menos society_id/match_confidence/matched_at, que são nossos),
  # e os sócios ganham last_seen_release; quem saiu do QSA fica com a release
  # antiga — é assim que se enxerga mudança de quadro societário.
  #
  # Mesmo esqueleto de lib/tasks/import_mg.rake: fatias, uma transação por
  # fatia, linha malformada contada e ignorada.
  class Importer
    SLICE = 2000

    def initialize(file:, release:, dry_run: false, logger: Rails.logger, source: ReceitaCompany::SOURCE_DUMP)
      @file = file
      @release = release
      @dry_run = dry_run
      @logger = logger
      @source = source
      @stats = Hash.new(0)
    end

    def call
      @logger.info("Receita::Importer: lendo #{@file} release=#{@release}#{@dry_run ? ' (DRY RUN)' : ''}")

      File.foreach(@file).each_slice(SLICE) do |lines|
        records = lines.filter_map { |line| parse(line) }
        next if records.empty? || @dry_run

        import_records(records)
        @logger.info("Receita::Importer: #{@stats[:read]} lidas, #{@stats[:companies_upserted]} empresas")
      end

      @stats
    end

    # Grava um lote de registros já parseados. Devolve quantas empresas foram
    # gravadas. Público porque o CnpjLookup reaproveita para a linha da API.
    def import_records(records)
      now = Time.current
      records = records.select { |r| r["cnpj"].to_s.length == 14 }.uniq { |r| r["cnpj"] }
      if @release.present?
        existing = ReceitaCompany.where(cnpj: records.map { |r| r["cnpj"] }, release: @release, source: @source).pluck(:cnpj).to_set
        records = records.reject { |r| existing.include?(r["cnpj"]) }
        @stats[:companies_unchanged] += existing.size
      end
      return 0 if records.empty?

      ActiveRecord::Base.transaction do
        companies = records.map { |r| RowMapper.company_attrs(r, source: @source, release: @release, now: now) }
        ReceitaCompany.upsert_all(companies, unique_by: :index_receita_companies_on_cnpj,
                                             update_only: RowMapper::COMPANY_UPDATE_COLUMNS)
        @stats[:companies_upserted] += companies.size

        ids = ReceitaCompany.where(cnpj: records.map { |r| r["cnpj"] }).pluck(:cnpj, :id).to_h
        partners = records.flat_map { |r| RowMapper.partner_attrs(r, company_id: ids.fetch(r["cnpj"]), release: @release, now: now) }
        partners.uniq! { |p| [ p[:receita_company_id], p[:name_normalized], p[:documento] ] }
        if partners.any?
          ReceitaPartner.upsert_all(partners, unique_by: :index_receita_partners_unique_member,
                                              update_only: RowMapper::PARTNER_UPDATE_COLUMNS)
          @stats[:partners_upserted] += partners.size
        end
      end

      records.size
    end

    private

    def parse(line)
      line = line.strip
      return nil if line.empty?

      record = JSON.parse(line)
      unless record.is_a?(Hash)
        @stats[:malformed_line] += 1
        return nil
      end

      @stats[:read] += 1
      if record["cnpj"].to_s.length != 14
        @stats[:skipped_no_cnpj] += 1
        return nil
      end
      record
    rescue JSON::ParserError => e
      @stats[:malformed_line] += 1
      @logger.warn("Receita::Importer: linha malformada ignorada: #{e.message[0, 80]}")
      nil
    end
  end
end
