class ScraperLawyerSerializer
  ENTERPRISE_THRESHOLD = 6

  def initialize(lawyer)
    @lawyer = lawyer
  end

  def as_json
    {
      id: @lawyer.id,
      full_name: @lawyer.full_name,
      oab_number: @lawyer.oab_number,
      oab_id: @lawyer.oab_id,
      situation: @lawyer.situation,
      city: @lawyer.city,
      state: @lawyer.state,
      address: @lawyer.address,
      phone_number_1: @lawyer.phone_number_1,
      phone_number_2: @lawyer.phone_number_2,
      email: @lawyer.email,
      instagram: @lawyer.instagram,
      website: @lawyer.website,
      has_society: @lawyer.has_society,
      supplementary_oabs: supplementary_oabs,
      societies: [],
      crm_data: @lawyer.crm_data || {}
    }
  end

  private

  def supplementary_oabs
    if @lawyer.principal_lawyer_id.present?
      principal = @lawyer.principal_lawyer
      siblings = principal.supplementary_lawyers.where.not(id: @lawyer.id)
      [principal.oab_id] + siblings.pluck(:oab_id)
    else
      @lawyer.supplementary_lawyers.pluck(:oab_id)
    end
  end
end
