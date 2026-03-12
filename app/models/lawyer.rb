class Lawyer < ApplicationRecord
  validates :oab_id, uniqueness: { case_sensitive: false }

  belongs_to :principal_lawyer, class_name: 'Lawyer', optional: true, foreign_key: 'principal_lawyer_id'
  has_many :supplementary_lawyers, class_name: 'Lawyer', foreign_key: 'principal_lawyer_id'
  has_many :lawyer_societies, dependent: :destroy
  has_many :societies, through: :lawyer_societies

  # Define attributes for society_basic_details JSON field
  store_accessor :society_basic_details, :insc, :nome_soci, :idt_soci, :sigla_uf, :url

  # Define attributes for crm_data JSON field
  # Core research fields
  store_accessor :crm_data,
    :researched,              # boolean - has this lawyer been researched?
    :last_research_date,      # date string - when was the last research done?
    :trial_active,            # boolean - is the lawyer actively practicing (has recent cases)?
    # Procstudio CRM fields
    :tried_procstudio,        # boolean - have we tried to contact for Procstudio?
    :mail_marketing,          # boolean - is this lawyer in our mail marketing list?
    :mail_marketing_origin,   # array - where did we get the email from? ["oab", "linkedin", "manual"]
    # Contact tracking
    :contacted,               # boolean - have we contacted this lawyer?
    :contacted_by,            # string - who contacted them?
    :contacted_when,          # date string - when were they contacted?
    :contact_notes            # string - notes about the contact

  before_save :normalize_data
  before_save :update_has_society

  private

  def normalize_data
    self.state = state.upcase if state.present?
    self.full_name = full_name.strip if full_name.present?
    self.oab_number = oab_number.strip if oab_number.present?
    self.social_name = social_name.strip if social_name.present?
    self.zip_address = zip_address.strip if zip_address.present?
  end

  def update_has_society
    # Update has_society based on whether there are any lawyer_societies
    self.has_society = lawyer_societies.any? if has_society.nil? || lawyer_societies.loaded?
  end
end
