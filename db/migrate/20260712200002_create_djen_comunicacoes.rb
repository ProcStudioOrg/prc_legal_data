class CreateDjenComunicacoes < ActiveRecord::Migration[8.1]
  def change
    create_table :djen_comunicacoes do |t|
      # O índice composto abaixo já cobre buscas por djen_monitoring_id.
      t.references :djen_monitoring, null: false, foreign_key: true, index: false
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

    # Único por monitoramento, não global: a mesma comunicação pode citar dois
    # advogados monitorados (co-patrocínio) e precisa existir para os dois.
    add_index :djen_comunicacoes, [ :djen_monitoring_id, :djen_id ], unique: true
    add_index :djen_comunicacoes, :numero_processo
    add_index :djen_comunicacoes, :pushed_at
  end
end
