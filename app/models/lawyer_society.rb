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
  #
  # `lawyers.has_society` é flag denormalizada E indexada
  # (index_lawyers_on_has_society), mas `Lawyer#update_has_society` só roda no
  # save do próprio Lawyer — criar o vínculo não salva o advogado. Sem isto o
  # flag nasce velho e o advogado some de qualquer filtro por has_society.
  # Fica no model, não no controller, para valer também para rake e console.
  after_save :sync_lawyer_has_society
  after_destroy :sync_lawyer_has_society
  after_destroy :destroy_orphan_society

  # Enum for partnership types - using string values for Rails 8 compatibility
  enum :partnership_type, {
    socio: 'Sócio',
    associado: 'Associado',
    socio_de_servico: 'Sócio de Serviço'
  }

  private

  # update_column: não dispara validação nem callback do Lawyer, e não mexe em
  # updated_at — é sincronização de cache, não edição de dado.
  def sync_lawyer_has_society
    return if lawyer_id.blank?

    Lawyer.where(id: lawyer_id)
          .update_all(has_society: LawyerSociety.exists?(lawyer_id: lawyer_id))
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