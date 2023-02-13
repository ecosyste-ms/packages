# frozen_string_literal: true

module Ecosystem
  class Actions < Base

    def check_status_url(package)
      package.repository_url
    end

    def fetch_package_metadata(name)
      parts = name.split('/')
      return nil if parts.length < 2
      return nil unless parts[0].match?(/^[a-z\d](?:[a-z\d]|-(?=[a-z\d])){0,38}$/) # valid github username
      full_name = parts[0..1].join('/')
      if parts.length > 2
        path = parts[2..-1].join('/') 
      else
        path = nil
      end

      yaml_path = path.present? ? "#{path}/action" : "action"

      json = get_json("https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://github.com/#{full_name}")
      return nil if json.nil?
      return nil if json['error'].present?
      
      yaml = get_raw_no_exception("https://raw.githubusercontent.com/#{full_name}/#{json['default_branch']}/#{yaml_path}.yml")

      if yaml.blank?
        yaml = get_raw_no_exception("https://raw.githubusercontent.com/#{full_name}/#{json['default_branch']}/#{yaml_path}.yaml")
      end
      
      return nil unless yaml.present?

      yaml = YAML.safe_load(yaml)

      json.merge('name' => name, 'repository_url' => "https://github.com/#{full_name}", 'yaml' => yaml, 'path' => path)
    rescue
      nil
    end

    def recently_updated_package_names
      get_json("https://repos.ecosyste.ms/api/v1/package_names/actions").first(20)
    rescue
      []
    end

    def download_url(package, version = nil)
      if version.present?
        version.metadata["download_url"]
      else
        return nil if package.repository_url.blank?
        return nil unless package.repository_url.include?('/github.com/')
        full_name = package.repository_url.gsub('https://github.com/', '').gsub('.git', '')
        
        "https://codeload.github.com/#{full_name}/tar.gz/refs/heads/#{package.metadata['default_branch'] || 'master'}"
      end
    end

    def all_package_names
      get_json("https://repos.ecosyste.ms/api/v1/package_names/actions")
    rescue
      []
    end

    def map_package_metadata(package)
      return nil unless package
      {
        name: package['name'],
        description: package['yaml']['description'].presence || package["description"],
        repository_url: package["repository_url"],
        licenses: package['license'],
        keywords_array: package['topics'],
        homepage: package["homepage"],
        tags_url: package["tags_url"],
        namespace: package["owner"],
        metadata: package['yaml'].merge('default_branch' => package['default_branch'], 'path' => package['path'])
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      return [] unless pkg_metadata[:tags_url]
      tags_json = get_json(pkg_metadata[:tags_url])
      return [] if tags_json.blank?

      tags_json.map do |tag|
        {
          number: tag['name'],
          published_at: tag['published_at'],
          metadata: {
            sha: tag['sha'],
            download_url: tag['download_url']
          }
        }
      end
    rescue StandardError
      []
    end

    def dependencies_metadata(name, version, package)
      return [] unless package[:repository_url]
      github_name_with_owner = GithubUrlParser.parse(package[:repository_url]) 
      return [] unless github_name_with_owner

      if package[:metadata]['path'].present?
        url = "https://raw.githubusercontent.com/#{github_name_with_owner}/#{version}/#{package[:metadata]['path']}/action.yml"
      else
        url = "https://raw.githubusercontent.com/#{github_name_with_owner}/#{version}/action.yml"
      end

      deps = get_raw_no_exception(url)
      return [] unless deps.present?
      Bibliothecary::Parsers::Actions.parse_manifest(deps).map do |dep|
        {
          package_name: dep[:name],
          requirements: dep[:requirement].chomp.precense || '*',
          kind: dep[:type],
          ecosystem: 'actions'
        }
      end
    rescue StandardError
      []
    end
  end
end
