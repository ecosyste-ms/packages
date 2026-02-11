# frozen_string_literal: true

module Ecosystem
  class Helm < Base

    def registry_url(package, version = nil)
      parts = package.name.split('/')
      return nil unless parts.length == 2

      repository, name = parts
      url = "https://artifacthub.io/packages/helm/#{repository}/#{name}"
      url += "/#{version}" if version
      url
    end

    def download_url(_package, _version = nil)
      nil
    end

    def documentation_url(package, _version = nil)
      registry_url(package)
    end

    def install_command(package, version = nil)
      parts = package.name.split('/')
      return nil unless parts.length == 2

      repository, name = parts
      repo_url = package.metadata&.dig('repository_url')
      version_flag = version ? " --version #{version}" : ""

      if repo_url
        "helm repo add #{repository} #{repo_url} && helm install #{name} #{repository}/#{name}#{version_flag}"
      else
        "helm install #{name} #{repository}/#{name}#{version_flag}"
      end
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

      pkg = fetch_package_metadata(package.name)
      return nil if pkg.present? && pkg.is_a?(Hash) && pkg["name"].present?

      # Fall back to a direct request if not cached
      response = request(url)
      "removed" if [400, 404, 410].include?(response.status)
    end

    def dependencies_metadata(name, version, _package)
      parts = name.split('/')
      return [] unless parts.length == 2

      repository, package_name = parts
      data = get_json("https://artifacthub.io/api/v1/packages/helm/#{repository}/#{package_name}/#{version}")
      deps = data.dig('data', 'dependencies') || []

      deps.map do |dep|
        dep_name = if dep['artifacthub_repository_name']
          "#{dep['artifacthub_repository_name']}/#{dep['name']}"
        else
          dep['name']
        end

        {
          package_name: dep_name,
          requirements: dep['version'] || '*',
          kind: 'runtime',
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    rescue
      []
    end

    def all_package_names
      packages = get_json("https://artifacthub.io/api/v1/helm-exporter")
      return [] unless packages.is_a?(Array)

      packages.filter_map do |pkg|
        repository_name = pkg.dig('repository', 'name')
        package_name = pkg['name']
        "#{repository_name}/#{package_name}" if repository_name && package_name
      end.uniq
    rescue
      []
    end

    def recently_updated_package_names
      response = get_json("https://artifacthub.io/api/v1/packages/search?kind=0&sort=last_updated&limit=60")
      packages = response['packages'] || []

      packages.filter_map do |pkg|
        repository_name = pkg.dig('repository', 'name')
        package_name = pkg['name']
        "#{repository_name}/#{package_name}" if repository_name && package_name
      end
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      parts = name.split('/')
      return nil unless parts.length == 2

      repository, package_name = parts
      get_json("https://artifacthub.io/api/v1/packages/helm/#{repository}/#{package_name}")
    rescue
      nil
    end

    def map_package_metadata(package)
      return false unless package.present?

      source_link = Array.wrap(package['links']).find { |l| l['name'] =~ /source/i }
      repo_url = source_link&.dig('url') || package.dig('repository', 'url')

      {
        name: "#{package.dig('repository', 'name')}/#{package['name']}",
        description: package['description'],
        homepage: package['home_url'],
        repository_url: repo_fallback(repo_url, nil),
        keywords_array: Array.wrap(package['keywords']).compact,
        licenses: package['license'] || 'Unknown',
        namespace: package.dig('repository', 'name'),
        downloads: 0,
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

    def purl_params(package, version = nil)
      parts = package.name.split('/')
      return super unless parts.length == 2

      repository, name = parts
      {
        type: purl_type,
        namespace: repository,
        name: name,
        version: version.try(:number)
      }
    end
  end
end
