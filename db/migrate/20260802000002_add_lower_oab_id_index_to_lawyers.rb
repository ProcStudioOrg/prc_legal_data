class AddLowerOabIdIndexToLawyers < ActiveRecord::Migration[8.1]
  # `Lawyer` valida `oab_id` com `uniqueness: { case_sensitive: false }`, o que
  # emite `WHERE LOWER(oab_id) = LOWER($1)`. O índice único existente é sobre a
  # coluna crua, então LOWER() não o usa: cada INSERT virava seq scan em 1,8
  # milhão de linhas. Medido no lote MG de 2026-08 — o import andava ~2.200
  # registros por vários minutos; com este índice, os 44.525 entram em minutos.
  def change
    add_index :lawyers, 'LOWER(oab_id)', name: 'index_lawyers_on_lower_oab_id', if_not_exists: true
  end
end
