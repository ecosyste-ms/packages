# frozen_string_literal: true

module Ecosystem
  class Terraform < Base
    
    def registry_url(package, version = nil)
      base_url = "https://registry.terraform.io/modules"
      parts = package.name.split('/')
      if parts.length == 3
        namespace, name, provider = parts
        "#{base_url}/#{namespace}/#{name}/#{provider}" + (version ? "/#{version}" : "")
      else
        "#{base_url}/#{package.name}"
      end
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
      
      module_source = package.name
      module_source += "?version=#{version}" if version
      
      "terraform init # with module \"example\" { source = \"#{module_source}\" }"
    end

    def check_status_url(package)
      parts = package.name.split('/')
      return nil unless parts.length == 3
      
      namespace, name, provider = parts
      "https://registry.terraform.io/v1/modules/#{namespace}/#{name}/#{provider}/versions"
    end

    def check_status(package)
      url = check_status_url(package)
      return nil unless url
      
      begin
        json = get_json(url)
        versions = json.dig('modules', 0, 'versions')
        return "removed" if !versions || versions.empty?
        nil
      rescue StandardError
        "removed"
      end
    end

    def all_package_names
      # Use the v2 API that the Terraform Registry website uses
      all_names = []
      page = 1
      page_size = 100
      
      loop do
        begin
          response = get_json("https://registry.terraform.io/v2/modules?page[size]=#{page_size}&page[number]=#{page}")
          modules = response.dig('data') || []
          
          break if modules.empty?
          
          modules.each do |mod|
            full_name = mod.dig('attributes', 'full-name')
            all_names << full_name if full_name
          end
          
          # Check if there's a next page
          next_page = response.dig('links', 'next')
          break unless next_page
          
          page += 1
          
          # Safety break to prevent infinite loops (limit to first 50 pages)
          break if page > 50
        rescue
          break
        end
      end
      
      all_names.uniq
    rescue
      []
    end

    def recently_updated_package_names
      # Get recently updated modules using v2 API sorted by recent activity
      begin
        response = get_json("https://registry.terraform.io/v2/modules?include=latest-version&page[size]=100&page[number]=1&sort=-updated")
        modules = response.dig('data') || []
        
        modules.map do |mod|
          mod.dig('attributes', 'full-name')
        end.compact
      rescue
        []
      end
    end

    def fetch_package_metadata(name)
      parts = name.split('/')
      return nil unless parts.length == 3
      
      namespace, module_name, provider = parts
      get_json("https://registry.terraform.io/v1/modules/#{namespace}/#{module_name}/#{provider}")
    rescue
      nil
    end

    def map_package_metadata(package)
      return false unless package.present?
      
      {
        name: package['id'],
        description: package['description'],
        homepage: repo_fallback(package['source'], nil),
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
          'trusted' => package['trusted'] || false,
          'latest_version' => package['versions']&.first.is_a?(Hash) ? package['versions'].first['version'] : package['versions']&.first,
          'owner' => package['owner']
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
            published_at: version['published_at'],
            licenses: pkg_metadata[:licenses] || 'Unknown',
            metadata: {
              'submodules' => version['submodules'],
              'providers' => version['providers'],
            }
          }
        end
    end

    def self.purl_type
      'terraform'
    end

    def purl(package, version = nil)
      # Terraform modules have namespace/name/provider format
      parts = package.name.split('/')
      return nil unless parts.length == 3
      
      namespace, name, provider = parts
      
      PackageURL.new(
        type: 'terraform',
        namespace: "#{namespace}/#{provider}",
        name: name,
        version: version.try(:number)
      ).to_s
    rescue
      nil
    end

    private

    def registry_url_from_parts(namespace, name, provider)
      "https://registry.terraform.io/modules/#{namespace}/#{name}/#{provider}"
    end
  end
end