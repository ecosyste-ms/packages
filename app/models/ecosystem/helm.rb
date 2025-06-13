# frozen_string_literal: true

module Ecosystem
  class Helm < Base
    
    def registry_url(package, version = nil)
      base_url = "https://artifacthub.io/packages/helm"
      parts = package.name.split('/')
      if parts.length == 2
        repository, name = parts
        "#{base_url}/#{repository}/#{name}" + (version ? "/#{version}" : "")
      else
        "#{base_url}/#{package.name}"
      end
    end

    def download_url(package, version = nil)
      # Artifact Hub doesn't provide direct download URLs
      # Users need to add the repository and install via helm
      nil
    end

    def documentation_url(package, _version = nil)
      registry_url(package)
    end

    def install_command(package, version = nil)
      parts = package.name.split('/')
      return nil unless parts.length == 2
      
      repository, name = parts
      version_flag = version ? " --version #{version}" : ""
      
      "helm repo add #{repository} <REPO_URL> && helm install #{name} #{repository}/#{name}#{version_flag}"
    end

    def check_status_url(package)
      parts = package.name.split('/')
      return nil unless parts.length == 2
      
      repository, name = parts
      "https://artifacthub.io/api/v1/packages/helm/#{repository}/#{name}"
    end

    def check_status(package)
      url = check_status_url(package)
      return nil unless url
      
      begin
        get_json(url)
        nil
      rescue StandardError
        "removed"
      end
    end

    def all_package_names
      # Get all Helm packages from Artifact Hub helm-exporter endpoint
      begin
        packages = get_json("https://artifacthub.io/api/v1/helm-exporter")
        return [] unless packages.is_a?(Array)
        
        packages.map do |pkg|
          repository_name = pkg.dig('repository', 'name')
          package_name = pkg['name']
          "#{repository_name}/#{package_name}" if repository_name && package_name
        end.compact.uniq
      rescue
        []
      end
    end

    def recently_updated_package_names
      # Get recently updated Helm packages
      begin
        response = get_json("https://artifacthub.io/api/v1/packages/search?kind=0&sort=last_updated&limit=100")
        packages = response['packages'] || []
        
        packages.map do |pkg|
          repository_name = pkg.dig('repository', 'name')
          package_name = pkg['name']
          "#{repository_name}/#{package_name}" if repository_name && package_name
        end.compact
      rescue
        []
      end
    end

    def fetch_package_metadata(name)
      parts = name.split('/')
      return nil unless parts.length == 2
      
      repository, package_name = parts
      get_json("https://artifacthub.io/api/v1/packages/helm/#{repository}/#{package_name}")
    rescue
      nil
    end

    def map_package_metadata(package)
      return false unless package.present?
      
      {
        name: "#{package.dig('repository', 'name')}/#{package['name']}",
        description: package['description'],
        homepage: package['home_url'] || registry_url_from_parts(package.dig('repository', 'name'), package['name']),
        repository_url: repo_fallback(package['repository_url'], nil),
        keywords_array: Array.wrap(package['keywords']).compact,
        licenses: package['license'] || 'Unknown',
        namespace: package.dig('repository', 'name'),
        downloads: 0, # Artifact Hub doesn't provide download counts
        downloads_period: 'total',
        versions: package['available_versions'] || [],
        metadata: {
          'app_version' => package['app_version'],
          'chart_version' => package['version'],
          'category' => package['category'],
          'official' => package['official'] || false,
          'deprecated' => package['deprecated'] || false,
          'repository_url' => package.dig('repository', 'url'),
          'maintainers' => package['maintainers'] || []
        }
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      return [] unless pkg_metadata[:versions]
      
      pkg_metadata[:versions]
        .select { |v| v['version'].present? }
        .reject { |v| existing_version_numbers.include?(v['version']) }
        .map do |version|
          {
            number: version['version'],
            published_at: version['ts'] ? Time.at(version['ts']).utc : nil,
            licenses: pkg_metadata[:licenses] || 'Unknown',
            metadata: {
              'app_version' => version['app_version'],
              'contains_security_updates' => version['contains_security_updates'] || false,
              'prerelease' => version['prerelease'] || false
            }
          }
        end
    end

    def self.purl_type
      'helm'
    end

    def purl(package, version = nil)
      parts = package.name.split('/')
      return nil unless parts.length == 2
      
      repository, name = parts
      
      PackageURL.new(
        type: 'helm',
        namespace: repository,
        name: name,
        version: version.try(:number)
      ).to_s
    rescue
      nil
    end

    private

    def registry_url_from_parts(repository, name)
      "https://artifacthub.io/packages/helm/#{repository}/#{name}"
    end
  end
end