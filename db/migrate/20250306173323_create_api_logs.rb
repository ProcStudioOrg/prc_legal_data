class CreateApiLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :api_logs do |t|
      t.integer :user_id
      t.integer :api_key_id
      t.string :endpoint
      t.string :ip_address
      t.string :request_method
      t.integer :response_status
      t.integer :request_size
      t.float :response_time
      t.string :country_code
      t.string :browser

      t.timestamps
    end
  end
end
