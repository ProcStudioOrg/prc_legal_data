# app/serializers/society_serializer.rb
class SocietySerializer
  def initialize(society, options = {})
    @society = society
    @options = options
    @include_lawyers = options.fetch(:include_lawyers, true)
  end

  def as_json
    return nil unless @society

    base_attributes.merge(lawyer_attributes).merge(capacity_attributes)
  end

  def self.serialize_collection(societies, options = {})
    societies.map { |society| new(society, options).as_json }
  end

  private

  def base_attributes
    {
      id: @society.id,
      name: @society.name,
      oab_id: @society.oab_id,
      inscricao: @society.inscricao,
      state: @society.state,
      city: @society.city,
      address: @society.address,
      zip_code: @society.zip_code,
      phone: @society.phone,
      phone_number_2: @society.phone_number_2,
      situacao: @society.situacao,
      number_of_partners: @society.number_of_partners,
      society_link: @society.society_link,
      created_at: @society.created_at,
      updated_at: @society.updated_at
    }
  end

  def lawyer_attributes
    return {} unless @include_lawyers

    lawyers_data = @society.lawyer_societies.includes(:lawyer).map do |ls|
      lawyer = ls.lawyer
      {
        id: lawyer.id,
        full_name: lawyer.full_name,
        social_name: lawyer.social_name,
        oab_id: lawyer.oab_id,
        oab_number: lawyer.oab_number,
        state: lawyer.state,
        city: lawyer.city,
        situation: lawyer.situation,
        profession: lawyer.profession,
        profile_picture: format_lawyer_image(lawyer.profile_picture),
        partnership_type: ls.partnership_type,
        partnership_type_label: ls.partnership_type_before_type_cast
      }
    end

    { lawyers: lawyers_data }
  end

  def capacity_attributes
    {
      current_partners: @society.lawyers.count,
      remaining_spots: @society.remaining_spots,
      at_capacity: @society.at_capacity?
    }
  end

  def format_lawyer_image(image_name)
    return nil unless image_name.present?

    s3_config = Rails.application.config.s3
    bucket = s3_config[:profile_pictures_bucket]

    "https://#{bucket}.s3.amazonaws.com/#{image_name}"
  end
end
