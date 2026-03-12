# db/migrate/YYYYMMDDHHMMSS_add_requested_oab_to_api_logs.rb
class AddRequestedOabToApiLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :api_logs, :requested_oab, :string
    add_index :api_logs, :requested_oab
  end
end