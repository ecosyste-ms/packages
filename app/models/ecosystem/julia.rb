# frozen_string_literal: true

module Ecosystem
  class Julia < Base

    def sync_in_batches?
      true
    end

    def registry_url(package, version = nil)
      "#{@registry_url}/ui/Packages/General/#{package.name}/#{version}"
    end

    def check_status(package)
      url = check_status_url(package)
      connection = Faraday.new do |faraday|
        faraday.use Faraday::FollowRedirects::Middleware
        faraday.adapter Faraday.default_adapter
      end

      response = connection.head(url)
      "removed" if [400, 404, 410].include?(response.status)
    end

    def check_status_url(package)
      "#{@registry_url}/docs/General/#{package['name']}/stable/pkg.json"
    end

    def download_url(package, version = nil)
      if version.present?
        version.metadata["download_url"]
      else
        return nil if package.repository_url.blank?
        return nil unless package.repository_url.include?('/github.com/')
        full_name = package.repository_url.gsub('https://github.com/', '').gsub('.git', '')
        
        "https://codeload.github.com/#{full_name}/tar.gz/refs/heads/master"
      end
    end

    def install_command(package, version = nil)
      if version
        "Pkg.add(\"#{package.name}@#{version}\")"
      else
        "Pkg.add(\"#{package.name}\")"
      end
    end

    def packages
      @packages ||= begin
        get_json("#{@registry_url}/app/packages/info")['packages']
      rescue
        {}
      end
    end

    def all_package_names
      packages.map{|p| p['name'] }
    end

    def recently_updated_package_names
      u = "https://github.com/JuliaRegistries/General/commits/master/Registry.toml.atom"
      titles = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      titles.map { |t| t.split(" ")[2] }.uniq
    rescue
      []
    end

    def fetch_package_metadata(name)
      packages.find{|pkg| pkg['name'] == name}
    end

    def map_package_metadata(package)
      return false unless package
      package_name = "General/#{package['name']}"
      slug = 'stable'
      json = get_json("#{@registry_url}/docs/#{package_name}/#{slug}/pkg.json") rescue nil
      json = {} if json.nil?
      {
        name: package['name'],
        description: json['description'],
        homepage: json['homepage'],
        repository_url: repo_fallback(json['url'], json['homepage']),
        keywords_array: json['tags'],
        licenses: json['license'],
        downloads: fetch_downloads(package['name']),
        downloads_period: 'total',
        metadata: {
          uuid: json['uuid']
        }
      }
    end

    def fetch_downloads(package_name)
      url = "https://juliahub.com/v1/graphql"
      query = {
        operationName: "PackageStats",
        variables: { name: package_name },
        query: <<~GRAPHQL
          query PackageStats($name: String!) {
            packageStats: packagestats(where: {package: {name: {_eq: $name}}}) {
              downloads
              users
              uuid
              package {
                name
              }
            }
          }
        GRAPHQL
      }

      response = Faraday.post(url) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.headers['Accept'] = '*/*'
        req.headers['x-hasura-role'] = 'anonymous'
        req.headers['x-juliahub-ensure-js'] = 'true'
        req.body = query.to_json
      end
    
      json = JSON.parse(response.body) rescue {}

      json.dig('data', 'packageStats')&.first&.fetch('users', nil)
    rescue
      nil
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      version_numbers = get_json("#{@registry_url}/docs/General/#{pkg_metadata[:name]}/versions.json")
      version_numbers.map do |v|
        version_json = get_json("#{@registry_url}/docs/General/#{pkg_metadata[:name]}/#{v}/pkg.json")
        next if version_json.nil?
        {
          number: version_json['version'],
          published_at: version_json['release_date'],
          licenses: version_json['license'],
          metadata: {
            slug: version_json['slug'],
            uuid: version_json['uuid'],
          }
        }
      end.compact
    end

    def dependencies_metadata(name, version, package)
      json = get_json("#{@registry_url}/docs/General/#{package[:name]}/#{version}/pkg.json")
      json['deps'].map do |dep|
        next if dep['direct'] == false
        next if dep['versions'].join(',') == '*' # skip std libraries
        {
          package_name: dep['name'],
          requirements: dep['versions'].join(','),
          kind: 'runtime',
          ecosystem: self.class.name.demodulize.downcase
        }
      end.compact
    end
  end
end
