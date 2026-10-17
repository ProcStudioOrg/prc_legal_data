# DJEN watch no longer requires the lawyer to exist in the scraped base: an
# OAB the scraper has not reached yet is watched by its own oab_id. Add-only —
# existing rows keep lawyer_id and are not touched.
class AllowDjenMonitoringWithoutLawyer < ActiveRecord::Migration[8.1]
  def change
    change_column_null :djen_monitorings, :lawyer_id, true
    add_column :djen_monitorings, :oab_id, :string
    add_column :djen_monitorings, :djen_advogado_id, :bigint
    add_index :djen_monitorings, :oab_id, unique: true, where: "lawyer_id IS NULL"
    add_check_constraint :djen_monitorings, "lawyer_id IS NOT NULL OR oab_id IS NOT NULL",
                         name: "djen_monitorings_lawyer_or_oab"
  end
end
