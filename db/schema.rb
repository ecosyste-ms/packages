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

ActiveRecord::Schema[7.1].define(version: 2024_03_11_135604) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "advisories", force: :cascade do |t|
    t.bigint "source_id", null: false
    t.string "uuid"
    t.string "url"
    t.string "title"
    t.text "description"
    t.string "origin"
    t.string "severity"
    t.datetime "published_at"
    t.datetime "withdrawn_at"
    t.string "classification"
    t.float "cvss_score"
    t.string "cvss_vector"
    t.string "references", default: [], array: true
    t.string "source_kind"
    t.string "identifiers", default: [], array: true
    t.json "packages", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_id"], name: "index_advisories_on_source_id"
  end

  create_table "dependencies", force: :cascade do |t|
    t.integer "package_id"
    t.integer "version_id"
    t.string "package_name"
    t.string "ecosystem"
    t.string "kind"
    t.boolean "optional", default: false
    t.string "requirements"
    t.index ["ecosystem", "package_name"], name: "index_dependencies_on_ecosystem_and_package_name"
    t.index ["package_id"], name: "index_dependencies_on_package_id"
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
    t.bigint "total_downloads"
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

  create_table "mentions", force: :cascade do |t|
    t.integer "paper_id"
    t.integer "project_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["paper_id"], name: "index_mentions_on_paper_id"
    t.index ["project_id"], name: "index_mentions_on_project_id"
  end

  create_table "packages", force: :cascade do |t|
    t.integer "registry_id"
    t.string "name"
    t.string "ecosystem"
    t.text "description"
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
    t.json "advisories", default: [], null: false
    t.integer "maintainers_count", default: 0
    t.datetime "first_release_published_at"
    t.string "keywords", default: [], array: true
    t.integer "docker_dependents_count"
    t.bigint "docker_downloads_count"
    t.json "issue_metadata"
    t.boolean "critical"
    t.index "(((rankings ->> 'average'::text))::double precision)", name: "index_packages_on_rankings_average"
    t.index "lower((repository_url)::text)", name: "index_packages_on_lower_repository_url"
    t.index "registry_id, (((repo_metadata ->> 'forks_count'::text))::integer)", name: "index_packages_on_forks_count"
    t.index "registry_id, (((repo_metadata ->> 'stargazers_count'::text))::integer)", name: "index_packages_on_stargazers_count"
    t.index ["critical"], name: "index_packages_on_critical", where: "(critical = true)"
    t.index ["keywords"], name: "index_packages_on_keywords", using: :gin
    t.index ["latest_release_published_at"], name: "index_packages_on_latest_release_published_at"
    t.index ["registry_id", "dependent_packages_count"], name: "index_packages_on_registry_id_and_dependent_packages_count"
    t.index ["registry_id", "dependent_repos_count"], name: "index_packages_on_registry_id_and_dependent_repos_count"
    t.index ["registry_id", "docker_downloads_count"], name: "index_packages_on_registry_id_and_docker_downloads_count"
    t.index ["registry_id", "downloads"], name: "index_packages_on_registry_id_and_downloads"
    t.index ["registry_id", "name"], name: "index_packages_on_registry_id_and_name", unique: true
    t.index ["registry_id", "namespace"], name: "index_packages_on_registry_id_and_namespace"
    t.index ["registry_id", "updated_at"], name: "index_packages_on_registry_id_and_updated_at"
    t.index ["repository_url"], name: "index_packages_on_repository_url"
    t.index ["status", "last_synced_at"], name: "index_packages_on_status_and_last_synced_at"
  end

  create_table "papers", force: :cascade do |t|
    t.string "doi"
    t.string "openalex_id"
    t.string "title"
    t.datetime "publication_date"
    t.json "openalex_data"
    t.integer "mentions_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["doi"], name: "index_papers_on_doi"
  end

  create_table "projects", force: :cascade do |t|
    t.string "czi_id"
    t.string "ecosystem"
    t.string "name"
    t.json "package"
    t.integer "mentions_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ecosystem", "name"], name: "index_projects_on_ecosystem_and_name"
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
    t.integer "namespaces_count", default: 0
    t.string "version"
    t.integer "keywords_count", default: 0
    t.integer "versions_count"
    t.bigint "downloads"
  end

  create_table "sources", force: :cascade do |t|
    t.string "name"
    t.string "kind"
    t.string "url"
    t.integer "advisories_count", default: 0
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.integer "registry_id"
    t.index ["package_id", "number"], name: "index_versions_on_package_id_and_number", unique: true
    t.index ["package_id"], name: "index_versions_on_package_id"
    t.index ["published_at"], name: "index_versions_on_published_at"
    t.index ["registry_id"], name: "index_versions_on_registry_id"
  end

  add_foreign_key "advisories", "sources"
end
