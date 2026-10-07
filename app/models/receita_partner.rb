# frozen_string_literal: true

# Membro do QSA de um ReceitaCompany. `documento` é o CPF mascarado
# (`***146406**`) ou o CNPJ cheio quando o sócio é pessoa jurídica.
# `lawyer_id` é preenchido por Receita::SocietyMatcher (sócio de sociedade
# casada) ou Receita::PartnerLinker (nome único na UF).
class ReceitaPartner < ApplicationRecord
  belongs_to :receita_company
  belongs_to :lawyer, optional: true

  PESSOA_FISICA = 'Pessoa Física'

  scope :pessoa_fisica, -> { where(identificador: PESSOA_FISICA) }
  scope :linked, -> { where.not(lawyer_id: nil) }
  scope :unlinked, -> { where(lawyer_id: nil) }
end
