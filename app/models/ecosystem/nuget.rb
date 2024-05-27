# frozen_string_literal: true

module Ecosystem
  class Nuget < Base
    def registry_url(package, version = nil)
      "#{@registry_url}/packages/#{package.name}/#{version}"
    end

    def download_url(package, version)
      return nil unless version.present?
      "https://api.nuget.org/v3-flatcontainer/#{package.name.downcase}/#{version}/#{package.name.downcase}.#{version}.nupkg"
    end

    def install_command(package, version = nil)
      "Install-Package #{package.name}" + (version ? " -Version #{version}" : "")
    end

    def check_status_url(package)
      "https://api.nuget.org/v3-flatcontainer/#{package.name.downcase}/index.json"
    end

    def check_status(package)
      url = check_status_url(package)
      response = Faraday.get(url)
      return "removed" if [400, 404, 410].include?(response.status)

      url = registry_url(package)
      response = Faraday.get(url)
      return "removed" if [400, 404, 410].include?(response.status)
      return "removed" if response.body.include? 'This package has been deleted from the gallery.'
      return "removed" if response.body.include? "This package's content is hidden"
    end

    def recently_updated_package_names
      name_endpoints.reverse[0..1].map { |url| get_names(url) }.flatten.uniq
    rescue
      []
    end

    def name_endpoints
      get("https://api.nuget.org/v3/catalog0/index.json")["items"].map { |i| i["@id"] }
    end

    def get_names(endpoint)
      get(endpoint)["items"].map { |i| i["nuget:id"] }
    end

    def all_package_names
      endpoints = name_endpoints
      segment_count = endpoints.length - 1

      names = []
      endpoints.reverse[0..segment_count].each do |endpoint|
        package_ids = get_names(endpoint)
        package_ids.each { |id| names << id.downcase }
      end
      return names
    rescue
      []
    end

    def fetch_package_metadata(name)
      h = {
        name: name,
      }
      h[:releases] = get_releases(name)
      h[:download_stats] = download_stats(name)
      h[:versions] = versions_metadata(h)
      
      return {} unless h[:versions].any?

      h
    end

    def download_stats(name)
      get_json("https://azuresearch-usnc.nuget.org/query?q=packageid:#{name.downcase}")
    rescue
      {}
    end

    def get_releases(name)
      latest_version = get_json("https://api.nuget.org/v3/registration5-semver1/#{name.downcase}/index.json")
      if latest_version["items"][0]["items"]
        releases = []
        latest_version["items"].each do |items|
          releases << items["items"]
        end
        releases.flatten!
      elsif releases.nil?
        releases = []
        latest_version["items"].each do |page|
          json = get_json(page["@id"])
          releases << json["items"]
        end
        releases.flatten!
      end
      releases
    rescue StandardError
      []
    end

    def map_package_metadata(package)
      return false if package[:releases].nil?
      item = package[:releases].last["catalogEntry"]

      {
        name: package[:name].try(:downcase),
        description: description(item),
        homepage: item["projectUrl"],
        keywords_array: Array(item["tags"]).reject(&:blank?),
        repository_url: repo_fallback("", item["packageUrl"]),
        releases: package[:releases],
        licenses: item["licenseExpression"],
        downloads: package[:download_stats]['data'].try(:first).try(:fetch,'totalDownloads'),
        downloads_period: 'total',
        download_stats: package[:download_stats],
      }
    end

    def description(item)
      item["description"].blank? ? item["summary"] : item["description"]
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkg_metadata[:releases].map do |item|
        {
          number: item["catalogEntry"]["version"],
          published_at: item["catalogEntry"]["published"],
          metadata: {
            downloads: version_downloads(pkg_metadata, item["catalogEntry"]["version"])
          }
        }
      end
    end

    def version_downloads(pkg_metadata, version)
      return nil unless pkg_metadata[:download_stats] && pkg_metadata[:download_stats]['data'].present?
      pkg_metadata[:download_stats]['data'][0]['versions'].find{|v| v['version'] == version}.try(:fetch,'downloads')
    rescue
      nil
    end

    def dependencies_metadata(_name, version, package)
      current_version = package[:releases].find { |v| v["catalogEntry"]["version"] == version }
      dep_groups = current_version.fetch("catalogEntry", {})["dependencyGroups"] || []

      deps = dep_groups.map do |dep_group|
        next unless dep_group["dependencies"]

        dep_group["dependencies"].map do |dependency|
          {
            name: dependency["id"],
            requirements: parse_requirements(dependency["range"]),
          }
        end
      end.flatten.compact

      deps.map do |dep|
        {
          package_name: dep[:name].downcase,
          requirements: dep[:requirements],
          kind: "runtime",
          optional: false,
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end

    def parse_requirements(range)
      return unless range.present?

      parts = range[1..-2].split(",")
      requirements = []
      low_bound = range[0]
      high_bound = range[-1]
      low_number = parts[0].strip
      high_number = parts[1].try(:strip)

      # lowest
      low_sign = low_bound == "[" ? ">=" : ">"
      high_sign = high_bound == "]" ? "<=" : "<"

      # highest
      if high_number != low_number
        requirements << "#{low_sign} #{low_number}" if low_number.present?
        requirements << "#{high_sign} #{high_number}" if high_number.present?
      elsif high_number == low_number
        requirements << "= #{high_number}"
      elsif low_number.present?
        requirements << "#{low_sign} #{low_number}"
      end
      requirements << ">= 0" if requirements.empty?
      requirements.join(" ")
    end

    def maintainers_metadata(name)
      json = get_json("https://azuresearch-usnc.nuget.org/query?q=packageid:#{name.downcase}")
      json['data'][0]['owners'].map do |user|
        {
          uuid: user,
          login: user
        }
      end
    rescue StandardError
      []
    end

    def maintainer_url(maintainer)
      "https://www.nuget.org/profiles/#{maintainer.login}"
    end
  end
end
