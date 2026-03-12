# app/models/society.rb
class Society < ApplicationRecord
  has_many :lawyer_societies, dependent: :destroy
  has_many :lawyers, through: :lawyer_societies

  # Validations
  validates :inscricao, presence: true, uniqueness: true
  validates :name, presence: true
  validates :state, presence: true
  validates :number_of_partners, presence: true, numericality: { greater_than: 0 }

  # Custom validation to ensure we don't exceed the society size
  validate :lawyers_count_within_limit, if: :number_of_partners_changed?

  # Scopes
  scope :with_members, -> { joins(:lawyer_societies).distinct }
  scope :orphans, -> { left_joins(:lawyer_societies).where(lawyer_societies: { id: nil }) }

  # Check if society can accept more lawyers
  def can_add_lawyer?
    lawyers.count < number_of_partners
  end

  # Get remaining spots in the society
  def remaining_spots
    [number_of_partners - lawyers.count, 0].max
  end

  # Check if society is at capacity
  def at_capacity?
    lawyers.count >= number_of_partners
  end

  # Check if society has any members
  def has_members?
    lawyers.exists?
  end

  # Check if society is orphan (no members)
  def orphan?
    !has_members?
  end

  # Class method to clean up orphan societies
  def self.destroy_orphans!
    orphan_societies = orphans.to_a
    count = orphan_societies.count
    orphan_societies.each(&:destroy)
    Rails.logger.info("Destroyed #{count} orphan societies")
    count
  end

  private

  def lawyers_count_within_limit
    return unless persisted? # Skip for new records

    if lawyers.count > number_of_partners
      errors.add(:number_of_partners,
        "cannot be less than current number of associated lawyers (#{lawyers.count})")
    end
  end
end
