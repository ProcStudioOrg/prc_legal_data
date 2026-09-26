class AddClassifierCityIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!
  def change
    add_index :lawyers, "state, (regexp_replace(trim(translate(lower(city), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')), '\\s+', ' ', 'g'))", name: 'index_lawyers_classifier_city', algorithm: :concurrently, if_not_exists: true
  end
end
