class LawyerCrmSerializer
  PARTNER_LIMIT = 6

  # Sort buckets by partnership_type — must match LawyerSociety enum keys.
  PARTNERSHIP_SORT_ORDER = {
    "socio"            => 0,
    "socio_de_servico" => 1,
    "associado"        => 2
  }.freeze

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
    hash[:supplementaries] = @lawyer.supplementary_lawyers.map(&:oab_id)
    hash[:societies] = serialize_societies
    hash
  end

  private

  def blank_for_emit?(value)
    value.nil? || value == ""
  end

  def serialize_societies
    @lawyer.lawyer_societies.map { |ls| serialize_society(ls) }
  end

  def serialize_society(ls)
    society = ls.society
    soc_hash = {
      name: society.name,
      oab_id: society.oab_id,
      inscricao: society.inscricao
    }

    {
      state: society.state,
      city: society.city,
      address: society.address,
      phone: society.phone,
      situacao: society.situacao,
      number_of_partners: society.number_of_partners,
      partnership_type: ls.partnership_type
    }.each do |key, value|
      soc_hash[key] = value unless blank_for_emit?(value)
    end

    sorted = sorted_other_partners(society)
    soc_hash[:partners] = sorted.first(PARTNER_LIMIT).map { |partner_ls|
      LawyerCrmPartnerSerializer.new(partner_ls.lawyer, partnership_type: partner_ls.partnership_type).as_json
    }
    soc_hash[:truncated_partners] = sorted.length > PARTNER_LIMIT
    soc_hash[:truncated_partner_oabs] = if sorted.length > PARTNER_LIMIT
      sorted.drop(PARTNER_LIMIT).map { |partner_ls| { oab_id: partner_ls.lawyer.oab_id } }
    else
      []
    end

    soc_hash
  end

  def sorted_other_partners(society)
    society.lawyer_societies
      .reject { |partner_ls| partner_ls.lawyer_id == @lawyer.id }
      .sort_by { |partner_ls|
        [
          PARTNERSHIP_SORT_ORDER.fetch(partner_ls.partnership_type, 99),
          partner_ls.lawyer.oab_id.to_s
        ]
      }
  end
end
