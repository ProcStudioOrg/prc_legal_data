class LawyerCrmSerializer
  PARTNER_LIMIT = 6

  ALWAYS_EMIT_FIELDS = %i[crm_data supplementaries].freeze
  CONDITIONAL_FIELDS = %i[
    full_name oab_id state city situation profession address zip_code
    phone_number_1 phone_number_2
    phone_1_has_whatsapp phone_2_has_whatsapp
    email specialty bio instagram website is_procstudio
  ].freeze

  def initialize(lawyer)
    @lawyer = lawyer
  end

  def as_json
    return nil unless @lawyer

    hash = {}
    CONDITIONAL_FIELDS.each do |field|
      value = @lawyer.public_send(field)
      hash[field] = value unless blank_for_emit?(value)
    end
    hash[:crm_data] = @lawyer.crm_data || {}
    hash[:supplementaries] = []  # filled in by Task 3
    hash[:societies] = []        # filled in by Task 4+
    hash
  end

  private

  # Drop nil and empty strings only. Boolean false must survive.
  def blank_for_emit?(value)
    value.nil? || value == ""
  end
end
