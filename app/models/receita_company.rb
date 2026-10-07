# frozen_string_literal: true

# Estabelecimento da Receita Federal (dump OpenCNPJ ou API pública).
# Chave natural: `cnpj` (14 caracteres, unique). `cnpj_root` agrupa matriz e
# filiais. `society_id` só é preenchido pelo Receita::SocietyMatcher com
# confiança verified.
class ReceitaCompany < ApplicationRecord
  belongs_to :society, optional: true
  has_many :receita_partners, dependent: :delete_all

  SOURCE_DUMP = 'dump'
  SOURCE_API = 'opencnpj_api'

  # Naturezas jurídicas que são sociedade de advogados de verdade. Cartório e
  # órgão público também têm CNAE 6911701 e ficam fora por default.
  SOCIETY_NATURES = [
    'Sociedade Unipessoal de Advocacia',
    'Sociedade Simples Pura',
    'Sociedade Simples Limitada',
    'Sociedade Empresária Limitada',
    'Empresário (Individual)'
  ].freeze

  validates :cnpj, presence: true, length: { is: 14 }
  validates :cnpj_root, presence: true, length: { is: 8 }
  validates :source, inclusion: { in: [SOURCE_DUMP, SOURCE_API] }

  scope :ativas, -> { where(situacao_cadastral: 'Ativa') }
  scope :matrizes, -> { where(matriz: true) }
  scope :advocacia, -> { where(natureza_juridica: SOCIETY_NATURES) }
  scope :from_dump, -> { where(source: SOURCE_DUMP) }

  # Sócios presentes na release desta empresa. Para linha vinda da API (sem
  # release) devolve todos.
  def current_partners
    return receita_partners if release.blank?

    receita_partners.where(last_seen_release: release)
  end

  def unipessoal?
    natureza_juridica.to_s.include?('Unipessoal')
  end

  def negative_cache?
    source == SOURCE_API && raw.blank?
  end
end
