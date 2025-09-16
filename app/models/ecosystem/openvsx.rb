# frozen_string_literal: true

module Ecosystem
  class Openvsx < Base
    def registry_url(package, version = nil)
      raise NotImplementedError
    end

    def install_command(package, version = nil)
      raise NotImplementedError
    end

    def download_url(package, version)
      return nil unless version.present?
      raise NotImplementedError
    end

    def documentation_url(package, version = nil)
      raise NotImplementedError
    end

    def check_status_url(package)
      raise NotImplementedError
    end

    def all_package_names
      raise NotImplementedError
    end

    def recently_updated_package_names
      raise NotImplementedError
    end

    def fetch_package_metadata(name)
      raise NotImplementedError
    end

    def map_package_metadata(package)
      raise NotImplementedError
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      raise NotImplementedError
    end

    def dependencies_metadata(name, version, _package)
      raise NotImplementedError
    end

    def maintainers_metadata(name)
      raise NotImplementedError
    end

    def maintainer_url(maintainer)
      raise NotImplementedError
    end
  end
end
