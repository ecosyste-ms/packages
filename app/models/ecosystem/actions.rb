# frozen_string_literal: true

module Ecosystem
  class Actions < Base

    def check_status_url(package)
      package.repository_url
    end

    def check_status(package)
      return 'removed' if fetch_package_metadata(package.name).nil?
    end

    def fetch_package_metadata(name)
      parts = name.split('/')
      return nil if parts.length < 2
      return nil unless parts[0].match?(/^[a-z\d](?:[a-z\d]|-(?=[a-z\d])){0,38}$/i) # valid github username
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
      
      # TODO search for action.yml or action.yaml in all tags if not found in default branch
      tags = tags_json = get_json(json['tags_url']+'?per_page=1000')
      if tags.present?
        yaml = nil
        while yaml.blank? && tags.present?
          tag = tags.shift
          yaml = get_raw_no_exception("https://raw.githubusercontent.com/#{full_name}/#{tag['name']}/#{yaml_path}.yml")
          if yaml.blank?
            yaml = get_raw_no_exception("https://raw.githubusercontent.com/#{full_name}/#{tag['name']}/#{yaml_path}.yaml")
          end
        end
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
      tags_json = get_json(pkg_metadata[:tags_url]+'?per_page=1000')
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

    def crawl_marketplace_list(query, category, max_pages = 50)
      slugs = Set.new
      (1..max_pages).each do |page|
        url = "https://github.com/marketplace?page=#{page}&type=actions" + (category ? "&category=#{category}" : "") + (query ? "&query=#{query}" : "")
        response = Faraday.get(url)
        doc = Nokogiri::HTML(response.body)
        links = doc.css('.d-md-flex.flex-wrap.mb-4 a')
        break if links.blank?
        links.each do |link|
          slugs << link['href']
        end
        sleep 1
      end
      slugs
    end
    
    def crawl_marketplace_category(category)
      slugs = Set.new 
      ["created-desc", "created-asc", "popularity-desc", "popularity-asc"].each do |sort|
        slugs.merge crawl_marketplace_list("sort%3A#{sort}", category)
      end
      slugs
    end
    
    def crawl_marketplace
      slugs = Set.new
      fetch_marketplace_categories.each do |category|
        slugs.merge crawl_marketplace_category(category)
      end
      slugs
      convert_slugs_to_repos(slugs)
    end

    def crawl_recent_marketplace
      slugs = Set.new
      fetch_marketplace_categories.each do |category|
        slugs.merge crawl_marketplace_list("sort%3Acreated-desc", category, 1)
      end
      slugs
      convert_slugs_to_repos(slugs)
    end

    def fetch_marketplace_categories
      url = "https://github.com/marketplace?query=sort%3Apopularity-asc&type=actions"
      response = Faraday.get(url)
      doc = Nokogiri::HTML(response.body)
      categories = doc.css('.Link--muted.filter-item.py-2.mb-0').map { |link| link['href'] }
    
      category_slugs = categories.map do |category|
        Rack::Utils.parse_nested_query(URI.parse(category).query)['category']
      end.compact
    
      all_categories = Set.new
    
      category_slugs.each do |category_slug|
        all_categories << category_slug
        url = "https://github.com/marketplace?query=sort%3Apopularity-asc&type=actions&category=#{category_slug}"
        response = Faraday.get(url)
        doc = Nokogiri::HTML(response.body)
        sub_categories = doc.css('.Link--muted.filter-item.py-1.mb-0').map { |link| link['href'] }
        sub_categories_slugs = sub_categories.map do |category|
          Rack::Utils.parse_nested_query(URI.parse(category).query)['category']
        end.compact
        all_categories.merge sub_categories_slugs
        sleep 1
      end
      all_categories
    end
    
    def convert_slugs_to_repos(slugs)
      repo_names = Set.new
    
      slugs.each do |slug|
        begin
        url = "https://github.com#{slug}"
        response = Faraday.get(url)
        next unless response.success?
        doc = Nokogiri::HTML(response.body)
        name = doc.css('.octicon-repo').last.parent['href'].gsub('https://github.com/', '')
        repo_names << name
        rescue
          puts "Error: #{url}"
        end
        sleep 1
      end
      repo_names
    end
    
  end
end
