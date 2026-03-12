# app/models/lawyer_society.rb
class LawyerSociety < ApplicationRecord
  belongs_to :lawyer
  belongs_to :society

  # Validations to prevent duplicates
  validates :lawyer_id, uniqueness: { scope: :society_id }
  validates :partnership_type, presence: true

  # Custom validation to ensure society capacity isn't exceeded
  validate :society_has_capacity, on: :create

  # Callbacks
  after_destroy :destroy_orphan_society

  # Enum for partnership types - using string values for Rails 8 compatibility
  enum :partnership_type, {
    socio: 'Sócio',
    associado: 'Associado',
    socio_de_servico: 'Sócio de Serviço'
  }

  private

  def society_has_capacity
    return unless society

    unless society.can_add_lawyer?
      errors.add(:society,
        "is at full capacity (#{society.number_of_partners} lawyers maximum). " \
        "Currently has #{society.lawyers.count} lawyers.")
    end
  end

  # Auto-delete society when the last member association is removed
  def destroy_orphan_society
    return unless society

    # Reload to get fresh count after this record is destroyed
    if society.lawyers.count == 0
      Rails.logger.info("Auto-deleting orphan society #{society.id} (#{society.name}) - no members remaining")
      society.destroy
    end
  end
end