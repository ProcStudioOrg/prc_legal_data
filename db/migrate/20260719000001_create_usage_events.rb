class CreateUsageEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_events do |t|
      t.string :event_type, null: false
      t.string :ip_hash, null: false
      t.datetime :created_at, null: false
    end

    add_index :usage_events, :created_at
  end
end
