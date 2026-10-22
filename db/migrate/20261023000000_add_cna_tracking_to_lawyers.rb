class AddCnaTrackingToLawyers < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :lawyers, :cna_scraped_at, :datetime
    add_column :lawyers, :discovered_via, :string
    add_column :lawyers, :city_source, :string
    add_index :lawyers, :cna_scraped_at, where: "cna_scraped_at IS NULL", name: "index_lawyers_cna_pending", algorithm: :concurrently
    add_index :lawyers, :discovered_via, algorithm: :concurrently

    # Tudo que já existe veio de scrape (CNA 07/2025, lote MG, app CNA): carimba
    # a data de criação como data do scrape. Pendente = cna_scraped_at nulo.
    say_with_time "backfill cna_scraped_at" do
      loop do
        n = execute(<<~SQL).cmd_tuples
          UPDATE lawyers SET cna_scraped_at = created_at
          WHERE id IN (SELECT id FROM lawyers WHERE cna_scraped_at IS NULL LIMIT 20000)
        SQL
        break if n.zero?
      end
    end
  end

  def down
    remove_index :lawyers, name: "index_lawyers_cna_pending"
    remove_index :lawyers, :discovered_via
    remove_column :lawyers, :city_source
    remove_column :lawyers, :discovered_via
    remove_column :lawyers, :cna_scraped_at
  end
end
