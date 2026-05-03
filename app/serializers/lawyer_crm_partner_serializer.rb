class LawyerCrmPartnerSerializer
  CONDITIONAL_FIELDS = LawyerCrmSerializer::CONDITIONAL_FIELDS

  def initialize(lawyer, partnership_type:)
    @lawyer = lawyer
    @partnership_type = partnership_type
  end

  def as_json
    hash = {}
    CONDITIONAL_FIELDS.each do |field|
      value = @lawyer.public_send(field)
      hash[field] = value unless blank_for_emit?(value)
    end
    hash[:partnership_type] = @partnership_type
    hash[:profile_picture] = profile_picture_url if @lawyer.profile_picture.present?
    hash[:crm_data] = @lawyer.crm_data || {}
    hash[:supplementaries] = @lawyer.supplementary_lawyers.map(&:oab_id)
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
