# app/serializers/lawyer_serializer.rb
class LawyerSerializer
  def initialize(lawyer, options = {})
    @lawyer = lawyer
    @options = options
    @include_societies = options.fetch(:include_societies, true)
    @include_supplementaries = options.fetch(:include_supplementaries, false)
    @include_crm = options.fetch(:include_crm, false)
  end

  def as_json
    return nil unless @lawyer

    base_attributes
      .merge(society_attributes)
      .merge(supplementary_attributes)
      .merge(crm_attributes)
  end

  def self.serialize_collection(lawyers, options = {})
    lawyers.map { |lawyer| new(lawyer, options).as_json }
  end

  private

  def base_attributes
    {
      id: @lawyer.id,
      full_name: @lawyer.full_name,
      social_name: @lawyer.social_name,
      oab_number: @lawyer.oab_number,
      oab_id: @lawyer.oab_id,
      state: @lawyer.state,
      city: @lawyer.city,
      situation: @lawyer.situation,
      profession: @lawyer.profession,
      address: @lawyer.address,
      original_address: @lawyer.original_address,
      zip_code: @lawyer.zip_code,
      zip_address: @lawyer.zip_address,
      phone_number_1: @lawyer.phone_number_1,
      phone_number_2: @lawyer.phone_number_2,
      phone_1_has_whatsapp: @lawyer.phone_1_has_whatsapp,
      phone_2_has_whatsapp: @lawyer.phone_2_has_whatsapp,
      email: @lawyer.email,
      profile_picture: format_image_url(@lawyer.profile_picture, :profile),
      cna_picture: format_image_url(@lawyer.cna_picture, :cna),
      cna_link: @lawyer.cna_link,
      detail_url: @lawyer.detail_url,
      specialty: @lawyer.specialty,
      bio: @lawyer.bio,
      instagram: @lawyer.instagram,
      website: @lawyer.website,
      suplementary: @lawyer.suplementary,
      is_procstudio: @lawyer.is_procstudio,
      has_society: @lawyer.lawyer_societies.any?,
      created_at: @lawyer.created_at,
      updated_at: @lawyer.updated_at
    }
  end

  def society_attributes
    return {} unless @include_societies

    societies_data = @lawyer.lawyer_societies.includes(:society).map do |ls|
      society = ls.society
      {
        id: society.id,
        name: society.name,
        oab_id: society.oab_id,
        inscricao: society.inscricao,
        state: society.state,
        city: society.city,
        address: society.address,
        phone: society.phone,
        situacao: society.situacao,
        number_of_partners: society.number_of_partners,
        society_link: society.society_link,
        partnership_type: ls.partnership_type,
        partnership_type_label: ls.partnership_type_before_type_cast
      }
    end

    { societies: societies_data }
  end

  def supplementary_attributes
    return {} unless @include_supplementaries

    supplementaries = @lawyer.supplementary_lawyers.map do |supp|
      self.class.new(supp, include_societies: true, include_supplementaries: false).as_json
    end

    { supplementaries: supplementaries }
  end

  def crm_attributes
    return {} unless @include_crm

    { crm_data: @lawyer.crm_data || {} }
  end

  def format_image_url(image_name, type)
    return nil unless image_name.present?

    s3_config = Rails.application.config.s3
    bucket = type == :profile ? s3_config[:profile_pictures_bucket] : s3_config[:cna_pictures_bucket]

    "https://#{bucket}.s3.amazonaws.com/#{image_name}"
  end
end
