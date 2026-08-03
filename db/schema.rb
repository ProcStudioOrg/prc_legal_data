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

ActiveRecord::Schema[8.1].define(version: 2026_08_03_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "unaccent"

  create_table "api_keys", force: :cascade do |t|
    t.boolean "active"
    t.datetime "created_at", null: false
    t.string "key"
    t.string "role", default: "read", null: false
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

  create_table "djen_comunicacoes", force: :cascade do |t|
    t.boolean "ativo", default: true, null: false
    t.datetime "cancellation_pushed_at"
    t.datetime "created_at", null: false
    t.date "data_disponibilizacao"
    t.string "djen_hash"
    t.bigint "djen_id", null: false
    t.bigint "djen_monitoring_id", null: false
    t.jsonb "labels", default: [], null: false
    t.string "numero_processo"
    t.datetime "pushed_at"
    t.jsonb "raw", default: {}, null: false
    t.string "sigla_tribunal"
    t.datetime "updated_at", null: false
    t.index ["djen_monitoring_id", "djen_id"], name: "index_djen_comunicacoes_on_djen_monitoring_id_and_djen_id", unique: true
    t.index ["numero_processo"], name: "index_djen_comunicacoes_on_numero_processo"
    t.index ["pushed_at"], name: "index_djen_comunicacoes_on_pushed_at"
  end

  create_table "djen_monitorings", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "last_swept_at"
    t.bigint "lawyer_id", null: false
    t.datetime "onboarded_at"
    t.string "source", default: "procstudio", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_djen_monitorings_on_active"
    t.index ["lawyer_id"], name: "index_djen_monitorings_on_lawyer_id", unique: true
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
    t.string "cnpja_person_id"
    t.datetime "created_at", null: false
    t.jsonb "crm_data", default: {}, null: false
    t.string "detail_url"
    t.bigint "djen_advogado_id"
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
    t.index "lower((oab_id)::text)", name: "index_lawyers_on_lower_oab_id"
    t.index ["crm_data"], name: "index_lawyers_on_crm_data", using: :gin
    t.index ["djen_advogado_id"], name: "index_lawyers_on_djen_advogado_id"
    t.index ["full_name"], name: "index_lawyers_on_full_name"
    t.index ["has_society"], name: "index_lawyers_on_has_society"
    t.index ["oab_id"], name: "index_lawyers_on_oab_id", unique: true
    t.index ["principal_lawyer_id"], name: "index_lawyers_on_principal_lawyer_id"
  end

  create_table "societies", force: :cascade do |t|
    t.string "address"
    t.string "city"
    t.string "cnpj"
    t.jsonb "cnpja_data", default: {}, null: false
    t.string "cnpja_match_confidence"
    t.datetime "cnpja_synced_at"
    t.datetime "cnpja_updated_at"
    t.datetime "created_at", null: false
    t.jsonb "crm_data", default: {}, null: false
    t.string "email"
    t.integer "inscricao"
    t.string "name"
    t.integer "number_of_partners"
    t.string "oab_id"
    t.string "phone"
    t.string "phone_number_2"
    t.string "situacao"
    t.string "society_link"
    t.string "source"
    t.string "state"
    t.datetime "updated_at", null: false
    t.string "website"
    t.string "zip_code"
    t.index ["cnpj"], name: "index_societies_on_cnpj", unique: true, where: "(cnpj IS NOT NULL)"
    t.index ["crm_data"], name: "index_societies_on_crm_data", using: :gin
    t.index ["oab_id"], name: "index_societies_on_oab_id_portal", unique: true, where: "((source)::text = 'oab_portal'::text)"
    t.index ["source"], name: "index_societies_on_source"
    t.index ["state", "name"], name: "index_societies_on_state_and_name"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "usage_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "ip_hash", null: false
    t.index ["created_at"], name: "index_usage_events_on_created_at"
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
  add_foreign_key "djen_comunicacoes", "djen_monitorings"
  add_foreign_key "djen_monitorings", "lawyers"
  add_foreign_key "lawyer_societies", "lawyers"
  add_foreign_key "lawyer_societies", "societies"
  add_foreign_key "lawyers", "lawyers", column: "principal_lawyer_id"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
