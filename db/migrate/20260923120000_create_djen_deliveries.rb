# Ledger de entrega POR DESTINO. Até aqui `djen_comunicacoes.pushed_at` dizia
# "entregue" sem dizer a quem — bastava enquanto havia um ProcStudio só. Com
# HML e produção coexistindo, cada destino precisa do seu carimbo; senão o
# primeiro que recebe "rouba" a comunicação dos outros (foi o que deixou a
# produção sem intimação nenhuma em 2026-09).
#
# O backfill carimba tudo que já estava entregue como entregue AO DESTINO
# LEGADO (`PROCSTUDIO_BASE_URL` do .env no momento da migração). Sem essa
# variável e com linhas carimbadas, a migração recusa rodar: perder o carimbo
# significaria reenviar o ledger inteiro para o destino antigo.
class CreateDjenDeliveries < ActiveRecord::Migration[8.1]
  def up
    create_table :djen_deliveries do |t|
      # O índice composto abaixo já cobre buscas por djen_comunicacao_id.
      t.references :djen_comunicacao, null: false, foreign_key: true, index: false
      t.string :destination, null: false
      t.datetime :pushed_at
      t.datetime :cancellation_pushed_at

      t.timestamps
    end

    add_index :djen_deliveries, [ :djen_comunicacao_id, :destination ], unique: true
    add_index :djen_deliveries, [ :destination, :pushed_at ]

    if (legacy = legacy_destination)
      execute <<~SQL
        INSERT INTO djen_deliveries
          (djen_comunicacao_id, destination, pushed_at, cancellation_pushed_at, created_at, updated_at)
        SELECT id, #{quote(legacy)}, pushed_at, cancellation_pushed_at,
               pushed_at, COALESCE(cancellation_pushed_at, pushed_at)
        FROM djen_comunicacoes
        WHERE pushed_at IS NOT NULL
      SQL
    end

    remove_index :djen_comunicacoes, :pushed_at
    remove_column :djen_comunicacoes, :pushed_at, :datetime
    remove_column :djen_comunicacoes, :cancellation_pushed_at, :datetime
  end

  def down
    add_column :djen_comunicacoes, :pushed_at, :datetime
    add_column :djen_comunicacoes, :cancellation_pushed_at, :datetime
    add_index :djen_comunicacoes, :pushed_at

    legacy = ENV["PROCSTUDIO_BASE_URL"].to_s.strip
    if legacy.present?
      key = normalize(legacy)
      execute <<~SQL
        UPDATE djen_comunicacoes c
        SET pushed_at = d.pushed_at, cancellation_pushed_at = d.cancellation_pushed_at
        FROM djen_deliveries d
        WHERE d.djen_comunicacao_id = c.id AND d.destination = #{quote(key)}
      SQL
    end

    drop_table :djen_deliveries
  end

  private

  def legacy_destination
    stamped = select_value("SELECT COUNT(*) FROM djen_comunicacoes WHERE pushed_at IS NOT NULL").to_i
    legacy = ENV["PROCSTUDIO_BASE_URL"].to_s.strip

    if legacy.blank?
      return nil if stamped.zero?

      raise "#{stamped} comunicações já entregues, mas PROCSTUDIO_BASE_URL não está definida: " \
            "sem saber para QUAL ProcStudio elas foram, o backfill do ledger por destino é impossível. " \
            "Defina PROCSTUDIO_BASE_URL (o destino que recebia até agora) e rode a migração de novo."
    end

    normalize(legacy)
  end

  # Mesma regra de Djen::Destinations.normalize, inline para a migração não
  # depender do código da app (que pode mudar depois dela).
  def normalize(url)
    url = url.strip.sub(%r{/+\z}, "")
    url.sub(%r{\A(https?://[^/]+)}i) { |origin| origin.downcase }
  end
end
