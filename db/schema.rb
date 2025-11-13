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

ActiveRecord::Schema[8.1].define(version: 2025_11_13_124934) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_stat_statements"

  create_table "advisories", force: :cascade do |t|
    t.string "classification"
    t.datetime "created_at", null: false
    t.float "cvss_score"
    t.string "cvss_vector"
    t.text "description"
    t.string "identifiers", default: [], array: true
    t.string "origin"
    t.json "packages", default: {}
    t.datetime "published_at"
    t.string "references", default: [], array: true
    t.string "severity"
    t.bigint "source_id", null: false
    t.string "source_kind"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "uuid"
    t.datetime "withdrawn_at"
    t.index ["source_id"], name: "index_advisories_on_source_id"
  end

  create_table "dependencies", force: :cascade do |t|
    t.string "ecosystem"
    t.string "kind"
    t.boolean "optional", default: false
    t.integer "package_id"
    t.string "package_name"
    t.string "requirements"
    t.integer "version_id"
    t.index ["ecosystem", "package_name"], name: "index_dependencies_on_ecosystem_and_package_name"
    t.index ["package_id"], name: "index_dependencies_on_package_id"
    t.index ["version_id"], name: "index_dependencies_on_version_id"
  end

  create_table "exports", force: :cascade do |t|
    t.string "bucket_name"
    t.datetime "created_at", null: false
    t.string "date"
    t.integer "packages_count"
    t.datetime "updated_at", null: false
  end

  create_table "maintainers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "login"
    t.string "name"
    t.boolean "organization"
    t.integer "packages_count", default: 0
    t.integer "registry_id"
    t.bigint "total_downloads"
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "uuid"
    t.index ["registry_id", "login"], name: "index_maintainers_on_registry_id_and_login", unique: true
    t.index ["registry_id", "uuid"], name: "index_maintainers_on_registry_id_and_uuid", unique: true
  end

  create_table "maintainerships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "maintainer_id"
    t.integer "package_id"
    t.string "role"
    t.datetime "updated_at", null: false
    t.index ["maintainer_id"], name: "index_maintainerships_on_maintainer_id"
    t.index ["package_id", "maintainer_id"], name: "index_maintainerships_on_package_id_and_maintainer_id", unique: true
  end

  create_table "mentions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "paper_id"
    t.integer "project_id"
    t.datetime "updated_at", null: false
    t.index ["paper_id"], name: "index_mentions_on_paper_id"
    t.index ["project_id"], name: "index_mentions_on_project_id"
  end

  create_table "packages", force: :cascade do |t|
    t.json "advisories", default: [], null: false
    t.datetime "created_at", null: false
    t.boolean "critical"
    t.integer "dependent_packages_count", default: 0
    t.integer "dependent_repos_count", default: 0
    t.text "description"
    t.integer "docker_dependents_count"
    t.bigint "docker_downloads_count"
    t.bigint "downloads"
    t.string "downloads_period"
    t.string "ecosystem"
    t.datetime "first_release_published_at"
    t.string "homepage"
    t.json "issue_metadata"
    t.string "keywords", default: [], array: true
    t.string "keywords_array", default: [], array: true
    t.string "language"
    t.datetime "last_synced_at"
    t.string "latest_release_number"
    t.datetime "latest_release_published_at"
    t.string "licenses"
    t.integer "maintainers_count", default: 0
    t.json "metadata", default: {}
    t.string "name"
    t.string "namespace"
    t.string "normalized_licenses", default: [], array: true
    t.json "rankings", default: {}
    t.integer "registry_id"
    t.json "repo_metadata", default: {}
    t.datetime "repo_metadata_updated_at"
    t.string "repository_url"
    t.string "status"
    t.datetime "updated_at", null: false
    t.integer "versions_count", default: 0, null: false
    t.datetime "versions_updated_at"
    t.index "(((rankings ->> 'average'::text))::double precision)", name: "index_packages_on_rankings_average"
    t.index "(((repo_metadata ->> 'stargazers_count'::text))::integer) DESC NULLS LAST", name: "index_packages_on_stargazers_desc", where: "(length((repo_metadata)::text) > 2)"
    t.index "lower((repository_url)::text)", name: "index_packages_on_lower_repository_url"
    t.index "registry_id, (((repo_metadata ->> 'forks_count'::text))::integer)", name: "index_packages_on_forks_count"
    t.index "registry_id, (((repo_metadata ->> 'stargazers_count'::text))::integer)", name: "index_packages_on_stargazers_count"
    t.index "registry_id, ((metadata ->> 'normalized_name'::text))", name: "index_packages_on_registry_id_and_normalized_name", where: "((metadata ->> 'normalized_name'::text) IS NOT NULL)"
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
    t.datetime "created_at", null: false
    t.string "doi"
    t.integer "mentions_count"
    t.json "openalex_data"
    t.string "openalex_id"
    t.datetime "publication_date"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["doi"], name: "index_papers_on_doi"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "czi_id"
    t.string "ecosystem"
    t.integer "mentions_count"
    t.string "name"
    t.json "package"
    t.datetime "updated_at", null: false
    t.index ["ecosystem", "name"], name: "index_projects_on_ecosystem_and_name"
  end

  create_table "registries", force: :cascade do |t|
    t.integer "active_packages_count", default: 0
    t.datetime "created_at", null: false
    t.boolean "default", default: false
    t.bigint "dependent_repos_count", default: 0
    t.bigint "downloads"
    t.string "ecosystem"
    t.string "github"
    t.integer "keywords_count", default: 0
    t.integer "maintainers_count", default: 0
    t.json "metadata", default: {}
    t.string "name"
    t.integer "namespaces_count", default: 0
    t.integer "packages_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "version"
    t.integer "versions_count"
  end

  create_table "sources", force: :cascade do |t|
    t.integer "advisories_count", default: 0
    t.datetime "created_at", null: false
    t.string "kind"
    t.json "metadata", default: {}
    t.string "name"
    t.datetime "updated_at", null: false
    t.string "url"
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "integrity"
    t.boolean "latest"
    t.string "licenses"
    t.json "metadata", default: {}
    t.string "number"
    t.integer "package_id"
    t.datetime "published_at"
    t.integer "registry_id"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["package_id", "number"], name: "index_versions_on_package_id_and_number", unique: true
    t.index ["published_at"], name: "index_versions_on_published_at"
    t.index ["registry_id"], name: "index_versions_on_registry_id"
  end

  add_foreign_key "advisories", "sources"
end
