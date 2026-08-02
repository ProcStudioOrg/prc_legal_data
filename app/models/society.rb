# app/models/society.rb
class Society < ApplicationRecord
  has_many :lawyer_societies, dependent: :destroy
  has_many :lawyers, through: :lawyer_societies

  OAB_PORTAL = 'oab_portal'

  # Validations
  #
  # `inscricao` é o número OAB da sociedade e continua obrigatório para tudo que
  # vem do CNA. As sociedades descobertas no portal da OAB-MG não têm esse
  # número — o portal não o expõe — e são identificadas pelo `oab_id`
  # (MG_<ordem>_SOCIEDADE), com índice único parcial no banco.
  validates :inscricao, presence: true, unless: :portal_sourced?
  validates :inscricao, uniqueness: true, allow_nil: true
  validates :oab_id, presence: true, if: :portal_sourced?
  validates :name, presence: true
  validates :state, presence: true
  validates :number_of_partners, presence: true, numericality: { greater_than: 0 }

  scope :from_oab_portal, -> { where(source: OAB_PORTAL) }

  def portal_sourced?
    source == OAB_PORTAL
  end

  # Scopes
  scope :with_members, -> { joins(:lawyer_societies).distinct }
  scope :orphans, -> { left_joins(:lawyer_societies).where(lawyer_societies: { id: nil }) }

  # Informativo, não mais um portão. `number_of_partners` é o retrato do quadro
  # societário na data do scrape, não um limite jurídico — ver LawyerSociety.
  def can_add_lawyer?
    true
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

  # Sobe o teto informativo quando a realidade já o ultrapassou. O número do CNA
  # é um retrato datado: o lote MG de 2026-08 trouxe 289 sociedades com mais
  # sócios reais do que o `number_of_partners` registrado.
  def sync_number_of_partners!
    real = lawyers.count
    return if real.zero? || real <= number_of_partners.to_i

    update_column(:number_of_partners, real)
  end
end
