# frozen_string_literal: true

require "csv"

EXPORT_VERSION = "1.0.0"
EXPORT_DATE = "2023-10-17"

namespace :open_data do
  desc "Export all open data csvs"
  task export: %i[
    export_packages
    export_versions
    export_dependencies
    export_packages_with_repository_fields
  ]

  desc "Export packages open data csv"
  task export_packages: :environment do
    csv_file = File.open("data/packages-#{EXPORT_VERSION}-#{EXPORT_DATE}.csv", "w")
    csv_file = CSV.new(csv_file)
    csv_file << [
      "ID",
      "Ecosystem",
      "Registry",
      "Name",
      "Namespace",
      "Created Timestamp",
      "Updated Timestamp",
      "Description",
      "Keywords",
      "Homepage URL",
      "Licenses",
      "Repository URL",
      "Versions Count",
      "Latest Release Publish Timestamp",
      "Latest Release Number",
      "Dependent Packages Count",
      "Language",
      "Status",
      "Last synced Timestamp",
      "Dependent Repositories Count",
      "Downloads",
      "Downloads Period",
      "Maintainers count",
      "First Release Publish Timestamp",
      "Docker Dependents Count",
      "Docker Downloads Count",
      "Advisories Count",
    ]

    Package.active.includes(:registry).find_each do |package|
      csv_file << [
        package.id,
        package.ecosystem,
        package.registry.name,
        package.name,
        package.namespace,
        package.created_at,
        package.updated_at,
        package.description.try(:tr, "\r\n", " "),
        package.keywords.join(",").try(:tr, "\r\n", " "),
        package.homepage.try(:tr, "\r\n", " ").try(:strip),
        package.normalized_licenses.join(","),
        package.repository_url.try(:tr, "\r\n", " ").try(:strip),
        package.versions_count,
        package.latest_release_published_at,
        package.latest_release_number,
        package.dependent_packages_count,
        package.language,
        package.status,
        package.last_synced_at,
        package.dependent_repos_count,
        package.downloads,
        package.downloads_period,
        package.maintainers_count,
        package.first_release_published_at,
        package.docker_dependents_count,
        package.docker_downloads_count,
        package.advisories.length,
      ]
    end
  end

  desc "Export packages with repository fields open data csv"
  task export_packages_with_repository_fields: :environment do
    csv_file = File.open("data/packages_with_repository_fields-#{EXPORT_VERSION}-#{EXPORT_DATE}.csv", "w")
    csv_file = CSV.new(csv_file)
    csv_file << [
      "ID",
      "Ecosystem",
      "Registry",
      "Name",
      "Namespace",
      "Created Timestamp",
      "Updated Timestamp",
      "Description",
      "Keywords",
      "Homepage URL",
      "Licenses",
      "Repository URL",
      "Versions Count",
      "Latest Release Publish Timestamp",
      "Latest Release Number",
      "Dependent Packages Count",
      "Language",
      "Status",
      "Last synced Timestamp",
      "Dependent Repositories Count",
      "Downloads",
      "Downloads Period",
      "Maintainers count",
      "First Release Publish Timestamp",
      "Docker Dependents Count",
      "Docker Downloads Count",
      "Advisories Count",
      "Repository UUID",
      "Repository Host Type",
      "Repository Host URL",
      "Repository Name with Owner",
      "Repository HTML URL",
      "Repository Description",
      "Repository Fork?",
      "Repository Created Timestamp",
      "Repository Updated Timestamp",
      "Repository Last pushed Timestamp",
      "Repository Dependencies Last synced Timestamp",
      "Repository Homepage URL",
      "Repository Size",
      "Repository Stars Count",
      "Repository Language",
      "Repository Issues enabled?",
      "Repository Wiki enabled?",
      "Repository Pages enabled?",
      "Repository Forks Count",
      "Repository Mirror URL",
      "Repository Open Issues Count",
      "Repository Default branch",
      "Repository Watchers Count",
      "Repository Fork Source Name with Owner",
      "Repository License",
      "Repository Readme filename",
      "Repository Changelog filename",
      "Repository Contributing guidelines filename",
      "Repository Funding filename",
      "Repository License filename",
      "Repository Code of Conduct filename",
      "Repository Security Threat Model filename",
      "Repository Security Audit filename",
      "Repository Citation filename",
      "Repository Codeowners filename",
      "Repository Security Policy filename",
      "Repository Support filename",
      "Repository Governance filename",
      "Repository Status",
      "Repository Last Synced Timestamp",
      "Repository SCM type",
      "Repository Pull requests enabled?",
      "Repository Icon URL",
      "Repository Topics",
      "Repository Tags Count",
    ]

    Package.active.includes(:registry).find_each do |package|
      repo = package.repo_metadata.presence || {}
      repo = repo.with_indifferent_access
      metadata = repo.fetch(:metadata, {}).presence || {}
      files = metadata.dig(:files).presence || {}
      csv_file << [
        package.id,
        package.ecosystem,
        package.registry.name,
        package.name,
        package.namespace,
        package.created_at,
        package.updated_at,
        package.description.try(:tr, "\r\n", " "),
        package.keywords.join(",").try(:tr, "\r\n", " "),
        package.homepage.try(:tr, "\r\n", " ").try(:strip),
        package.normalized_licenses.join(","),
        package.repository_url.try(:tr, "\r\n", " ").try(:strip),
        package.versions_count,
        package.latest_release_published_at,
        package.latest_release_number,
        package.dependent_packages_count,
        package.language,
        package.status,
        package.last_synced_at,
        package.dependent_repos_count,
        package.downloads,
        package.downloads_period,
        package.maintainers_count,
        package.first_release_published_at,
        package.docker_dependents_count,
        package.docker_downloads_count,
        package.advisories.length,
        repo.dig(:uuid),
        repo.fetch(:host, {}).dig(:kind),
        repo.fetch(:host, {}).dig(:url),
        repo.dig(:full_name),
        repo.dig(:html_url),
        repo.dig(:description).try(:tr, "\r\n", " "),
        repo.dig(:fork),
        repo.dig(:created_at),
        repo.dig(:updated_at),
        repo.dig(:pushed_at),
        repo.dig(:dependencies_parsed_at),
        repo.dig(:homepage),
        repo.dig(:size),
        repo.dig(:stargazers_count),
        repo.dig(:language),
        repo.dig(:has_issues),
        repo.dig(:has_wiki),
        repo.dig(:has_pages),
        repo.dig(:forks_count),
        repo.dig(:mirror_url),
        repo.dig(:open_issues_count),
        repo.dig(:default_branch),
        repo.dig(:subscribers_count),
        repo.dig(:source_name),
        repo.dig(:license),
        files.dig(:readme).presence || "",
        files.dig(:changelog).presence || "",
        files.dig(:contributing).presence || "",
        files.dig(:funding).presence || "",
        files.dig(:license).presence || "",
        files.dig(:code_of_conduct).presence || "",
        files.dig(:threat_model).presence || "",
        files.dig(:audit).presence || "",
        files.dig(:citation).presence || "",
        files.dig(:codeowners).presence || "",
        files.dig(:security).presence || "",
        files.dig(:support).presence || "",
        files.dig(:governance).presence || "",
        repo.dig(:status),
        repo.dig(:last_synced_at),
        repo.dig(:scm),
        repo.dig(:pull_requests_enabled),
        repo.dig(:icon_url),
        repo.dig(:topics).try(:join, ","),
        repo.dig(:tags_count),
      ]
    end
  end

  desc "Export versions open data csv"
  task export_versions: :environment do
    csv_file = File.open("data/versions-#{EXPORT_VERSION}-#{EXPORT_DATE}.csv", "w")
    csv_file = CSV.new(csv_file)
    csv_file << [
      "ID",
      "Ecosystem",
      "Registry",
      "Package Name",
      "Package ID",
      "Number",
      "License",
      "Integrity",
      "Status",
      "Published Timestamp",
      "Created Timestamp",
      "Updated Timestamp",
    ]

    Package.active.includes(:versions,:registry).find_each do |package|
      package.versions.each do |version|
        csv_file << [
          version.id,
          package.ecosystem,
          package.registry.name,
          package.name,
          package.id,
          version.number.try(:tr, "\r\n", " "),
          version.licenses.try(:tr, "\r\n", " "),
          version.integrity.try(:tr, "\r\n", " "),
          version.status,
          version.published_at,
          version.created_at,
          version.updated_at,
        ]
      end
    end
  end

  desc "Export dependencies open data csv"
  task export_dependencies: :environment do
    csv_file = File.open("data/dependencies-#{EXPORT_VERSION}-#{EXPORT_DATE}.csv", "w")
    csv_file = CSV.new(csv_file)
    csv_file << [
      "ID",
      "Ecosystem",
      "Registry",
      "Package Name",
      "Package ID",
      "Version Number",
      "Version ID",
      "Dependency Name",
      "Dependency Ecosystem",
      "Dependency Kind",
      "Optional Dependency",
      "Dependency Requirements",
      "Dependency Package ID",
    ]

    Package.active.includes(:registry, versions: :dependencies).find_each do |package|
      package.versions.each do |version|
        version.dependencies.each do |dependency|
          csv_file << [
            dependency.id,
            package.ecosystem,
            package.registry.name,
            package.name,
            package.id,
            version.number,
            version.id,
            dependency.package_name.try(:tr, "\r\n", ""),
            dependency.ecosystem.try(:tr, "\r\n", ""),
            dependency.kind.try(:tr, "\r\n", ""),
            dependency.optional,
            dependency.requirements.try(:tr, "\r\n", ""),
            dependency.package_id,
          ]
        end
      end
    end
  end
end
