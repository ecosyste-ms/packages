# frozen_string_literal: true

module Ecosystem
  class Puppet < Base

    def purl(package, version = nil)
      Purl::PackageURL.new(
        type: purl_type,
        namespace: package.name.split('-').first,
        name: package.name.split('-').last,
        version: version.try(:number).try(:encode,'iso-8859-1')
      ).to_s
    end

    def all_package_names
      offset = 0
      packages = []
      loop do
        results = get_json("#{@registry_url}/v3/modules?limit=100&offset=#{offset}")["results"].map { |result| result["slug"] }
        break if results == []

        packages += results
        offset += 100
      end
      packages
    rescue
      []
    end

    def fetch_package_metadata(name)
      get_json("#{@registry_url}/v3/modules/#{name}")
    rescue
      false
    end

    def map_package_metadata(package)
      return false unless package
      current_release = package["current_release"]
      return false if current_release.nil?
      metadata = current_release["metadata"]
      {
        name: package["slug"],
        repository_url: metadata["source"],
        homepage: metadata["project_page"],
        description: metadata["summary"],
        keywords_array: current_release["tags"],
        licenses: metadata["license"],
        releases: package['releases'],
        downloads: package['downloads'],
        downloads_period: 'total',
        namespace: package['owner']['slug'],
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkg_metadata[:releases].reject{|v| existing_version_numbers.include?(v['version'])}.sort_by{|v| v['version'] }.reverse.first(50).map do |release|
        version = get_json("#{@registry_url}/v3/releases/#{pkg_metadata[:name]}-#{release["version"]}")
        integrity = version['file_sha256'] ? 'sha256-' + version['file_sha256'] : nil        
        {
          number: release["version"],
          published_at: release["created_at"],
          integrity: integrity,
          metadata: {
            downloads: version['downloads']
          }
        }
      end
    end

    def dependencies_metadata(name, version, _mapped_package)
      release = get_json("#{@registry_url}/v3/releases/#{name}-#{version}")
      metadata = release["metadata"]
      metadata["dependencies"].map do |dependency|
        {
          package_name: dependency["name"].sub("/", "-"),
          requirements: dependency["version_requirement"],
          kind: "runtime",
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end

    def recently_updated_package_names
      get_json("#{@registry_url}/v3/modules?limit=100&sort_by=latest_release")["results"].map { |result| result["slug"] }
    rescue
      []
    end

    def install_command(package, version = nil)
      "puppet module install #{package.name}" + (version ? " --version #{version}" : "")
    end

    def registry_url(package, version = nil)
      "#{@registry_url}/modules/#{package.name.sub('-', '/')}" + (version ? "/#{version}" : "")
    end

    def download_url(package, version)
      return nil unless version.present?
      "#{@registry_url}/v3/files/#{package.name}-#{version}.tar.gz"
    end

    def check_status(package)
      url = "#{@registry_url}/v3/modules/#{package.name}"
      response = Faraday.get(url)
      return "removed" if [400, 404, 410].include?(response.status)
      json = Oj.load(response.body)
      return "unpublished" if json && json["current_release"].blank?
    end
  end
end
