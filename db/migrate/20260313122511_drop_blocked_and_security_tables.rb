class DropBlockedAndSecurityTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :blocked_ips, if_exists: true
    drop_table :blocked_countries, if_exists: true
    drop_table :security_alerts, if_exists: true
  end

  def down
    create_table :blocked_ips do |t|
      t.string :ip_address
      t.string :reason
      t.datetime :expires_at
      t.timestamps
    end

    create_table :blocked_countries do |t|
      t.string :country_code
      t.string :reason
      t.timestamps
    end

    create_table :security_alerts do |t|
      t.text :message
      t.string :severity
      t.boolean :resolved
      t.timestamps
    end
  end
end
