# app/models/lawyer_society.rb
class LawyerSociety < ApplicationRecord
  belongs_to :lawyer
  belongs_to :society

  # Validations to prevent duplicates
  validates :lawyer_id, uniqueness: { scope: :society_id }
  validates :partnership_type, presence: true

  # NÃO existe mais portão de capacidade.
  #
  # `Society#number_of_partners` vem do CNA e é o retrato do quadro societário
  # na data do scrape, não um limite jurídico — nada impede uma banca de admitir
  # sócios depois. A validação antiga (`society_has_capacity`) era andaime do
  # scraper inicial e passou a rejeitar dado verdadeiro: no lote OAB-MG de
  # 2026-08 ela barraria 584 vínculos reais em 289 sociedades, 160 delas já
  # "cheias" antes do lote começar. O teto agora só é informativo e é reajustado
  # por `Society#sync_number_of_partners!`.

  # Callbacks
  after_destroy :destroy_orphan_society

  # Enum for partnership types - using string values for Rails 8 compatibility
  enum :partnership_type, {
    socio: 'Sócio',
    associado: 'Associado',
    socio_de_servico: 'Sócio de Serviço'
  }

  private

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