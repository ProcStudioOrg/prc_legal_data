class AddRoleToApiKeys < ActiveRecord::Migration[8.1]
  def change
    add_column :api_keys, :role, :string, default: "read", null: false
  end
end
