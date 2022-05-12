class Package < ApplicationRecord
  validates_presence_of :registry_id, :name, :ecosystem
  validates_uniqueness_of :name, scope: :registry_id

  belongs_to :registry
  counter_culture :registry
  has_many :versions
  has_many :dependencies, -> { group 'package_name' }, through: :versions

  scope :ecosystem, ->(ecosystem) { where(ecosystem: Ecosystem::Base.format_name(ecosystem)) }

  before_save  :update_details

  def install_command
    registry.ecosystem_instance.install_command(self)
  end

  def registry_url
    registry.ecosystem_instance.registry_url(self)
  end

  def documentation_url
    registry.ecosystem_instance.documentation_url(self)
  end

  def update_details
    normalize_licenses
    set_latest_release_published_at
    set_latest_release_number
  end

  def latest_version
    versions.sort.first
  end

  def set_latest_release_published_at
    self.latest_release_published_at = (latest_version.try(:published_at).presence || updated_at)
  end

  def set_latest_release_number
    self.latest_release_number = latest_version.try(:number)
  end

  def normalize_licenses
    self.normalized_licenses =
      if licenses.blank?
        []
      elsif licenses.length > 150
        ["Other"]
      else
        spdx = spdx_license
        if spdx.empty?
          ["Other"]
        else
          spdx
        end
      end
  end

  def spdx_license
    licenses
      .downcase
      .sub(/^\(/, "")
      .sub(/\)$/, "")
      .split("or")
      .flat_map { |l| l.split("and") }
      .map { |l| manual_license_format(l) }
      .flat_map { |l| l.split(/[,\/]/) }
      .map(&Spdx.method(:find))
      .compact
      .map(&:id)
  end

  def manual_license_format(license)
    # fixes "Apache License, Version 2.0" being incorrectly split on the comma
    license
      .gsub("apache license, version", "apache license version")
      .gsub("apache software license, version", "apache software license version")
  end

  def sync
    registry.sync_package(name)
  end

  def sync_async
    registry.sync_package_async(name)
  end

  def update_versions
    package_metadata = registry.ecosystem_instance.package_metadata(name)
    return false unless package_metadata
    versions_metadata = registry.ecosystem_instance.versions_metadata(package_metadata)

    versions_metadata.each do |version|
      if version[:integrity].present? && versions.select{|ver| ver.number == version[:number] }.length > 1
        v = versions.find{|ver| ver.integrity == version[:integrity] }
      else
        v = versions.find{|ver| ver.number == version[:number] }
      end
      if v
        v.update(version)
      else
        versions.create(version)
      end
    end
  end

  def update_versions_async
    UpdateVersionsWorker.perform_async(id)
  end

  def update_integrities_async
    return if versions.first.try(:download_url).blank?
    versions.find_each(&:update_integrity_async)
  end
end
