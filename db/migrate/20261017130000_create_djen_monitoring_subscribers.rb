# Which API key (consumer) holds each DJEN watch. A read key may pause only its
# own hold; the watch stops when the last holder leaves. Add-only.
class CreateDjenMonitoringSubscribers < ActiveRecord::Migration[8.1]
  def change
    create_table :djen_monitoring_subscribers do |t|
      t.references :djen_monitoring, null: false, foreign_key: true
      t.references :api_key, null: false, foreign_key: true
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :djen_monitoring_subscribers, %i[djen_monitoring_id api_key_id],
              unique: true, name: "index_djen_monitoring_subscribers_uniqueness"
  end
end
