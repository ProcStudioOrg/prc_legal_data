class LawyerCrmListSerializer
  CONDITIONAL_FIELDS = %i[
    full_name oab_id state city
    phone_number_1 phone_number_2 email
    instagram website
    has_society
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
    hash
  end

  private

  def blank_for_emit?(value)
    value.nil? || value == ""
  end
end
