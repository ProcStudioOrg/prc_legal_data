# Helpers compartilhados pelos endpoints de CRM de pessoa física (LawyersController)
# e pessoa jurídica (SocietiesController). Os dois gravam num campo `crm_data`
# JSONB livre e aceitam os mesmos sub-hashes de IA.
module CrmParams
  extend ActiveSupport::Concern

  # Namespaces de sub-hash livre aceitos dentro de crm_data. Esta lista É a
  # fronteira de whitelist: qualquer chave de topo fora dela é rejeitada pelo
  # strong params normal.
  FREEFORM_CRM_KEYS = %i[scraper outreach signals].freeze

  private

  # Recursively converts ActionController::Parameters (and nested hashes/arrays)
  # into a plain Ruby hash with stringified keys. Used to allow free-form
  # sub-hashes under the :scraper, :outreach, and :signals namespaces without
  # opening up arbitrary root-level params — the whitelist boundary is the
  # explicit FREEFORM_CRM_KEYS list.
  def deep_permit_hash(value)
    case value
    when ActionController::Parameters
      value.to_unsafe_h.transform_values { |v| deep_permit_hash(v) }.deep_stringify_keys
    when Hash
      value.transform_values { |v| deep_permit_hash(v) }.deep_stringify_keys
    when Array
      value.map { |v| deep_permit_hash(v) }
    else
      value
    end
  end

  # Mescla os sub-hashes livres presentes no request dentro de `crm_params`.
  def merge_freeform_crm_keys(crm_params)
    FREEFORM_CRM_KEYS.each do |key|
      raw = params[key]
      next if raw.blank?

      crm_params[key.to_s] = deep_permit_hash(raw)
    end

    crm_params
  end
end
