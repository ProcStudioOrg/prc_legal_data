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
      societies: serialize_societies,
      crm_data: @lawyer.crm_data || {}
    }
  end

  private

  def serialize_societies
    @lawyer.lawyer_societies.includes(society: { lawyer_societies: :lawyer }).map do |ls|
      society = ls.society
      member_count = society.lawyer_societies.size

      if member_count > ENTERPRISE_THRESHOLD
        { name: society.name, enterprise: true, member_count: member_count }
      else
        members = society.lawyer_societies.map do |member_ls|
          { name: member_ls.lawyer.full_name, oab_id: member_ls.lawyer.oab_id }
        end
        { name: society.name, members: members }
      end
    end
  end

  def supplementary_oabs
    if @lawyer.principal_lawyer_id.present?
      # Use in-memory filtering to cooperate with eager loading
      principal = @lawyer.principal_lawyer
      siblings = principal.supplementary_lawyers.reject { |s| s.id == @lawyer.id }
      [principal.oab_id] + siblings.map(&:oab_id)
    else
      @lawyer.supplementary_lawyers.map(&:oab_id)
    end
  end
end
