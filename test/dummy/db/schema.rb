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

ActiveRecord::Schema[8.1].define(version: 2025_12_16_041227) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "captain_hook_actions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action_class", null: false
    t.boolean "async", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "event_type", null: false
    t.integer "max_attempts", default: 5, null: false
    t.integer "priority", default: 100, null: false
    t.string "provider", null: false
    t.json "retry_delays", default: [30, 60, 300, 900, 3600], null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_captain_hook_actions_on_deleted_at"
    t.index ["provider", "event_type", "action_class"], name: "idx_captain_hook_actions_unique", unique: true
    t.index ["provider"], name: "index_captain_hook_actions_on_provider"
  end

  create_table "captain_hook_examples", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_captain_hook_examples_on_active"
    t.index ["name"], name: "index_captain_hook_examples_on_name"
  end

  create_table "captain_hook_incoming_event_actions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action_class", null: false
    t.integer "attempt_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.uuid "incoming_event_id", null: false
    t.datetime "last_attempt_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "locked_at"
    t.string "locked_by"
    t.integer "priority", default: 100, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["incoming_event_id"], name: "index_captain_hook_incoming_event_actions_on_incoming_event_id"
    t.index ["locked_at"], name: "index_captain_hook_incoming_event_actions_on_locked_at"
    t.index ["status", "priority", "action_class"], name: "idx_captain_hook_actions_processing_order"
    t.index ["status"], name: "index_captain_hook_incoming_event_actions_on_status"
  end

  create_table "captain_hook_incoming_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.string "dedup_state", default: "unique", null: false
    t.string "event_type", null: false
    t.string "external_id", null: false
    t.json "headers"
    t.integer "lock_version", default: 0, null: false
    t.json "metadata"
    t.json "payload"
    t.string "provider", null: false
    t.string "request_id"
    t.string "status", default: "received", null: false
    t.datetime "updated_at", null: false
    t.index ["archived_at"], name: "index_captain_hook_incoming_events_on_archived_at"
    t.index ["created_at"], name: "index_captain_hook_incoming_events_on_created_at"
    t.index ["event_type"], name: "index_captain_hook_incoming_events_on_event_type"
    t.index ["provider", "external_id"], name: "idx_captain_hook_incoming_events_idempotency", unique: true
    t.index ["provider"], name: "index_captain_hook_incoming_events_on_provider"
    t.index ["status"], name: "index_captain_hook_incoming_events_on_status"
  end

  create_table "captain_hook_providers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "rate_limit_period", default: 60
    t.integer "rate_limit_requests", default: 100
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_captain_hook_providers_on_active"
    t.index ["name"], name: "index_captain_hook_providers_on_name", unique: true
    t.index ["token"], name: "index_captain_hook_providers_on_token", unique: true
  end

  create_table "webhook_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type"
    t.string "external_id"
    t.jsonb "payload"
    t.datetime "processed_at"
    t.string "provider"
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_webhook_logs_on_external_id"
    t.index ["provider", "event_type"], name: "index_webhook_logs_on_provider_and_event_type"
  end

  add_foreign_key "captain_hook_incoming_event_actions", "captain_hook_incoming_events", column: "incoming_event_id"
end
