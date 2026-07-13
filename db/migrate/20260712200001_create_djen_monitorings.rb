class CreateDjenMonitorings < ActiveRecord::Migration[8.1]
  def change
    create_table :djen_monitorings do |t|
      t.references :lawyer, null: false, foreign_key: true, index: { unique: true }
      t.boolean :active, null: false, default: true
      t.string :source, null: false, default: "procstudio"
      t.datetime :last_swept_at
      t.datetime :onboarded_at

      t.timestamps
    end

    add_index :djen_monitorings, :active
  end
end
