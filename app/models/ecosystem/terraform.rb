# frozen_string_literal: true

module Ecosystem
  class Terraform < Base

    def registry_url(package, version = nil)
      parts = package.name.split('/')
      return nil unless parts.length == 3

      namespace, name, provider = parts
      url = "https://registry.terraform.io/modules/#{namespace}/#{name}/#{provider}"
      url += "/#{version}" if version
      url
    end

    def download_url(package, version = nil)
      return nil unless version.present?

      parts = package.name.split('/')
      return nil unless parts.length == 3

      namespace, name, provider = parts
      "https://registry.terraform.io/v1/modules/#{namespace}/#{name}/#{provider}/#{version}/download"
    end

    def documentation_url(package, _version = nil)
      registry_url(package)
    end

    def install_command(package, version = nil)
      parts = package.name.split('/')
      return nil unless parts.length == 3

      source = "\"#{package.name}\""
      version_line = version ? "\n  version = \"#{version}\"" : ""

      "module \"example\" {\n  source  = #{source}#{version_line}\n}"
    end

    def check_status_url(package)
      parts = package.name.split('/')
      return nil unless parts.length == 3

      namespace, name, provider = parts
      "https://registry.terraform.io/v1/modules/#{namespace}/#{name}/#{provider}"
    end

    def check_status(package)
      json = fetch_package_metadata(package.name)
      return nil if json.present? && json.is_a?(Hash) && json["id"].present?

      # Fall back to a direct request if not cached
      url = check_status_url(package)
      return nil unless url

      response = request(url)
      "removed" if [400, 404, 410].include?(response.status)
    end

    def all_package_names
      all_names = []
      page = 1
      page_size = 100

      loop do
        response = get_json("https://registry.terraform.io/v2/modules?page%5Bsize%5D=#{page_size}&page%5Bnumber%5D=#{page}")
        modules = response['data'] || []

        break if modules.empty?

        modules.each do |mod|
          full_name = mod.dig('attributes', 'full-name')
          all_names << full_name if full_name
        end

        break unless response.dig('links', 'next')
        page += 1
      end

      all_names.uniq
    rescue
      []
    end

    def recently_updated_package_names
      response = get_json("https://registry.terraform.io/v1/modules?limit=100&offset=0")
      modules = response['modules'] || []

      modules.filter_map do |mod|
        # id includes version suffix, strip it
        mod['id']&.split('/')&.first(3)&.join('/')
      end
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      parts = name.split('/')
      return nil unless parts.length == 3

      namespace, module_name, provider = parts
      get_json("https://registry.terraform.io/v1/modules/#{namespace}/#{module_name}/#{provider}")
    rescue
      nil
    end

    def map_package_metadata(package)
      return false unless package.present?

      # id includes version (e.g. "namespace/name/provider/1.0.0"), strip it
      name = package['id']&.split('/')&.first(3)&.join('/')

      {
        name: name,
        description: package['description'],
        homepage: package['source'],
        repository_url: repo_fallback(package['source'], nil),
        keywords_array: [],
        licenses: 'Unknown',
        namespace: package['namespace'],
        downloads: package['downloads'] || 0,
        downloads_period: 'total',
        versions: package['versions'] || [],
        metadata: {
          'provider' => package['provider'],
          'verified' => package['verified'] || false,
          'owner' => package['owner']
        }
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      return [] unless pkg_metadata[:versions]

      # Versions from the main endpoint are plain strings
      pkg_metadata[:versions]
        .reject { |v| existing_version_numbers.include?(v) }
        .map do |version|
          {
            number: version,
            published_at: nil,
            licenses: pkg_metadata[:licenses] || 'Unknown',
          }
        end
    end

    def self.purl_type
      'terraform'
    end

    def purl_params(package, version = nil)
      parts = package.name.split('/')
      return super unless parts.length == 3

      namespace, name, provider = parts
      {
        type: purl_type,
        namespace: "#{namespace}/#{provider}",
        name: name,
        version: version.try(:number)
      }
    end
  end
end
