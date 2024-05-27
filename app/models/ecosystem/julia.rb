# frozen_string_literal: true

module Ecosystem
  class Julia < Base

    def sync_in_batches?
      true
    end

    def registry_url(package, version = nil)
      "#{@registry_url}/ui/Packages/#{package.name}/#{package.metadata['slug']}/#{version}"
    end

    def check_status(package)
      return "removed" if package.metadata['slug'].blank?
      url = check_status_url(package)
      connection = Faraday.new do |faraday|
        faraday.use Faraday::FollowRedirects::Middleware
        faraday.adapter Faraday.default_adapter
      end

      response = connection.head(url)
      "removed" if [400, 404, 410].include?(response.status)
    end

    def check_status_url(package)
      "#{@registry_url}/docs/#{package['name']}/#{package.metadata['slug']}/pkg.json"
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

    def documentation_url(package, version = nil)
      "https://docs.juliahub.com/#{package.name}/#{package.metadata['slug']}/#{version}"
    end

    def install_command(package, version = nil)
      if version
        "Pkg.add(Pkg.PackageSpec(;name=\"#{package.name}\", version=\"#{version}\"))"
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
      return false unless package['metadata']['docslink']
      slug = package['metadata']['docslink'].split('/')[2]
      json = get_json("#{@registry_url}/docs/#{package['name']}/#{slug}/pkg.json") rescue nil
      json = {} if json.nil?
      {
        name: package['name'],
        description: package['metadata']['description'],
        homepage: json['homepage'],
        repository_url: repo_fallback(package['metadata']['repo'], json['homepage']),
        keywords_array: package['metadata']['tags'],
        versions: package['metadata']['versions'],
        licenses: package['license'],
        downloads: fetch_downloads(package),
        downloads_period: 'total',
        metadata: {
          uuid: package['uuid'],
          slug: slug
        }
      }
    end

    def fetch_downloads(package)
      j = get_json("https://pkgs.genieframework.com/api/v1/badge/#{package['name']}")
      j['message'].to_i
    rescue
      nil
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      begin
        repo_json = get_json("https://repos.ecosyste.ms/api/v1/repositories/lookup?url=#{CGI.escape(pkg_metadata[:repository_url])}")
        tags_json = get_json("https://repos.ecosyste.ms/api/v1/hosts/#{repo_json['host']['name']}/repositories/#{repo_json['full_name']}/tags")
      rescue
        tags_json = []
      end
      pkg_metadata[:versions].map do |v|
        hash = {
          number: v,
          published_at: nil,
          metadata: {}
        }
        
        if tags_json.any?
          tag = tags_json.find{|t| t['name'].to_s.downcase.delete_prefix('v') == v}
          if tag
            hash[:published_at] = tag['published_at']
            hash[:metadata] = {
              sha: tag['sha'],
              download_url: tag['download_url']
            }
          end
        end

        hash
      end
    end

    def dependencies_metadata(name, version, package)
      json = get_json("#{@registry_url}/docs/#{package[:name]}/#{package[:metadata][:slug]}/#{version}/pkg.json")
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
