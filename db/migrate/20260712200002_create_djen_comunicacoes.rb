class CreateDjenComunicacoes < ActiveRecord::Migration[8.1]
  def change
    create_table :djen_comunicacoes do |t|
      t.references :djen_monitoring, null: false, foreign_key: true
      t.bigint :djen_id, null: false
      t.string :djen_hash
      t.string :numero_processo
      t.string :sigla_tribunal
      t.date :data_disponibilizacao
      t.boolean :ativo, null: false, default: true
      t.jsonb :labels, null: false, default: []
      t.jsonb :raw, null: false, default: {}
      t.datetime :pushed_at
      t.datetime :cancellation_pushed_at

      t.timestamps
    end

    add_index :djen_comunicacoes, :djen_id, unique: true
    add_index :djen_comunicacoes, :numero_processo
    add_index :djen_comunicacoes, :pushed_at
  end
end
