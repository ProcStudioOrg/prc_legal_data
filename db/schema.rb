# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_13_122511) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "api_keys", force: :cascade do |t|
    t.boolean "active"
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_api_keys_on_user_id"
  end

  create_table "api_logs", force: :cascade do |t|
    t.integer "api_key_id"
    t.string "browser"
    t.string "country_code"
    t.datetime "created_at", null: false
    t.string "endpoint"
    t.string "ip_address"
    t.string "request_method"
    t.integer "request_size"
    t.string "requested_oab"
    t.integer "response_status"
    t.float "response_time"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["requested_oab"], name: "index_api_logs_on_requested_oab"
  end

  create_table "lawyer_societies", force: :cascade do |t|
    t.string "cna_link"
    t.datetime "created_at", null: false
    t.bigint "lawyer_id", null: false
    t.string "partnership_type"
    t.bigint "society_id", null: false
    t.datetime "updated_at", null: false
    t.index ["lawyer_id"], name: "index_lawyer_societies_on_lawyer_id"
    t.index ["society_id"], name: "index_lawyer_societies_on_society_id"
  end

  create_table "lawyers", force: :cascade do |t|
    t.string "address"
    t.text "bio"
    t.string "city"
    t.string "cna_link"
    t.string "cna_picture"
    t.datetime "created_at", null: false
    t.jsonb "crm_data", default: {}, null: false
    t.string "detail_url"
    t.string "email"
    t.string "folder_id"
    t.string "full_name"
    t.boolean "has_society", default: false
    t.string "instagram"
    t.boolean "is_procstudio"
    t.string "oab_id"
    t.string "oab_number"
    t.text "original_address"
    t.boolean "phone_1_has_whatsapp"
    t.boolean "phone_2_has_whatsapp"
    t.string "phone_number_1"
    t.string "phone_number_2"
    t.bigint "principal_lawyer_id"
    t.string "profession"
    t.string "profile_picture"
    t.string "situation"
    t.string "social_name"
    t.jsonb "society_basic_details"
    t.string "specialty"
    t.string "state"
    t.boolean "suplementary"
    t.datetime "updated_at", null: false
    t.string "website"
    t.string "zip_address"
    t.string "zip_code"
    t.index ["crm_data"], name: "index_lawyers_on_crm_data", using: :gin
    t.index ["full_name"], name: "index_lawyers_on_full_name"
    t.index ["has_society"], name: "index_lawyers_on_has_society"
    t.index ["oab_id"], name: "index_lawyers_on_oab_id", unique: true
    t.index ["principal_lawyer_id"], name: "index_lawyers_on_principal_lawyer_id"
  end

  create_table "societies", force: :cascade do |t|
    t.string "address"
    t.string "city"
    t.datetime "created_at", null: false
    t.integer "inscricao"
    t.string "name"
    t.integer "number_of_partners"
    t.string "oab_id"
    t.string "phone"
    t.string "phone_number_2"
    t.string "situacao"
    t.string "society_link"
    t.string "state"
    t.datetime "updated_at", null: false
    t.string "zip_code"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false
    t.datetime "created_at", null: false
    t.string "email"
    t.string "password_digest"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "api_keys", "users"
  add_foreign_key "lawyer_societies", "lawyers"
  add_foreign_key "lawyer_societies", "societies"
  add_foreign_key "lawyers", "lawyers", column: "principal_lawyer_id"
end
