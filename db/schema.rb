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

ActiveRecord::Schema[7.0].define(version: 2022_11_15_092616) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "dependencies", force: :cascade do |t|
    t.integer "package_id"
    t.integer "version_id"
    t.string "package_name"
    t.string "ecosystem"
    t.string "kind"
    t.boolean "optional", default: false
    t.string "requirements"
    t.index ["package_id"], name: "index_dependencies_on_package_id"
    t.index ["package_name"], name: "index_dependencies_on_package_name"
    t.index ["version_id"], name: "index_dependencies_on_version_id"
  end

  create_table "exports", force: :cascade do |t|
    t.string "date"
    t.string "bucket_name"
    t.integer "packages_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "maintainers", force: :cascade do |t|
    t.integer "registry_id"
    t.string "uuid"
    t.string "login"
    t.string "email"
    t.string "name"
    t.string "url"
    t.integer "packages_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["registry_id", "login"], name: "index_maintainers_on_registry_id_and_login", unique: true
    t.index ["registry_id", "uuid"], name: "index_maintainers_on_registry_id_and_uuid", unique: true
  end

  create_table "maintainerships", force: :cascade do |t|
    t.integer "package_id"
    t.integer "maintainer_id"
    t.string "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["maintainer_id"], name: "index_maintainerships_on_maintainer_id"
    t.index ["package_id"], name: "index_maintainerships_on_package_id"
  end

  create_table "packages", force: :cascade do |t|
    t.integer "registry_id"
    t.string "name"
    t.string "ecosystem"
    t.text "description"
    t.text "keywords"
    t.string "homepage"
    t.string "licenses"
    t.string "repository_url"
    t.string "normalized_licenses", default: [], array: true
    t.integer "versions_count", default: 0, null: false
    t.datetime "latest_release_published_at"
    t.string "latest_release_number"
    t.string "keywords_array", default: [], array: true
    t.string "language"
    t.string "status"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "metadata", default: {}
    t.json "repo_metadata", default: {}
    t.datetime "repo_metadata_updated_at"
    t.integer "dependent_packages_count", default: 0
    t.bigint "downloads"
    t.string "downloads_period"
    t.integer "dependent_repos_count", default: 0
    t.json "rankings", default: {}
    t.string "namespace"
    t.index "(((rankings ->> 'average'::text))::double precision)", name: "index_packages_on_rankings_average"
    t.index "registry_id, (((repo_metadata ->> 'forks_count'::text))::integer)", name: "index_packages_on_forks_count"
    t.index "registry_id, (((repo_metadata ->> 'stargazers_count'::text))::integer)", name: "index_packages_on_stargazers_count"
    t.index ["latest_release_published_at"], name: "index_packages_on_latest_release_published_at"
    t.index ["registry_id", "dependent_packages_count"], name: "index_packages_on_registry_id_and_dependent_packages_count"
    t.index ["registry_id", "dependent_repos_count"], name: "index_packages_on_registry_id_and_dependent_repos_count"
    t.index ["registry_id", "downloads"], name: "index_packages_on_registry_id_and_downloads"
    t.index ["registry_id", "name"], name: "index_packages_on_registry_id_and_name", unique: true
    t.index ["registry_id", "namespace"], name: "index_packages_on_registry_id_and_namespace"
  end

  create_table "registries", force: :cascade do |t|
    t.string "name"
    t.string "url"
    t.string "ecosystem"
    t.boolean "default", default: false
    t.integer "packages_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "github"
    t.json "metadata", default: {}
    t.integer "maintainers_count", default: 0
  end

  create_table "versions", force: :cascade do |t|
    t.integer "package_id"
    t.string "number"
    t.datetime "published_at"
    t.string "licenses"
    t.string "integrity"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "metadata", default: {}
    t.index ["package_id"], name: "index_versions_on_package_id"
    t.index ["published_at"], name: "index_versions_on_published_at"
  end

end
