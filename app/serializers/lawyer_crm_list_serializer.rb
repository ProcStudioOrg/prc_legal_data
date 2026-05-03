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
    hash[:profile_picture] = profile_picture_url if @lawyer.profile_picture.present?
    hash[:crm_data] = @lawyer.crm_data || {}
    hash
  end

  private

  def blank_for_emit?(value)
    value.nil? || value == ""
  end

  def profile_picture_url
    bucket = Rails.application.config.s3[:profile_pictures_bucket]
    "https://#{bucket}.s3.amazonaws.com/#{@lawyer.profile_picture}"
  end
end
