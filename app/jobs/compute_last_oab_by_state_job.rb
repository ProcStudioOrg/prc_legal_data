class ComputeLastOabByStateJob < ApplicationJob
  queue_as :default

  VALID_STATES = %w[
    AC AL AP AM BA CE DF ES GO MA
    MT MS MG PA PB PR PE PI RJ RN
    RS RO RR SC SP SE TO
  ].freeze

  def perform(state)
    state = state.upcase
    return unless VALID_STATES.include?(state)

    total = Lawyer.where("oab_id LIKE ?", "#{state}_%").count

    if total == 0
      result = {
        state: state,
        message: "Nenhum advogado encontrado para o estado #{state}",
        last_oab: nil,
        total_lawyers: 0,
        computed_at: Time.current.iso8601
      }
    else
      # Use PostgreSQL to extract the numeric part and find the max in SQL
      lawyer = Lawyer
        .where("oab_id LIKE ?", "#{state}_%")
        .order(Arel.sql("CAST(SPLIT_PART(oab_id, '_', 2) AS INTEGER) DESC"))
        .limit(1)
        .first

      result = {
        state: state,
        last_oab: lawyer.oab_id,
        oab_number: lawyer.oab_number,
        lawyer_name: lawyer.full_name,
        city: lawyer.city,
        situation: lawyer.situation,
        total_lawyers: total,
        updated_at: lawyer.updated_at,
        computed_at: Time.current.iso8601
      }
    end

    Rails.cache.write("last_oab_by_state:#{state}", result, expires_in: 6.hours)
    Rails.logger.info("ComputeLastOabByStateJob: cached result for #{state} (total: #{total})")
  end
end
