# frozen_string_literal: true

module Ecosystem
  class Npm < Base
    def registry_url(package, version = nil)
      "https://www.npmjs.com/package/#{package.name}" + (version ? "/v/#{version}" : "")
    end

    def download_url(package, version)
      return nil unless version.present?
      "#{@registry_url}/#{package.name}/-/#{package.name.split('/').last}-#{version}.tgz"
    end

    def install_command(package, version = nil)
      "npm install #{package.name}" + (version ? "@#{version}" : "")
    end

    def check_status_url(package)
      "#{@registry_url}/#{package.name.gsub('/', '%2F')}"
    end

    def check_status(package)
      url = check_status_url(package)
      response = Typhoeus.get(url)
      return "removed" if [400, 404, 410].include?(response.response_code)
      json = Oj.load(response.body)

      if json 
        return "unpublished" if json["versions"].blank?
        non_prerelease_versions = json["versions"].values.reject{|v| Semantic::Version.new(v['version']).pre}

        return "deprecated" if non_prerelease_versions.length > 0 && non_prerelease_versions.all? { |v| v["deprecated"] }
      end
    end

    def all_package_names
      get("https://raw.githubusercontent.com/nice-registry/all-the-package-names/master/names.json")
    rescue
      []
    end

    def recently_updated_package_names
      begin
        u = "#{@registry_url}/-/rss?descending=true&limit=50"
        rss_names = SimpleRSS.parse(get_raw(u)).items.map(&:title).uniq
      rescue
        rss_names = []
      end
      begin
        recent_names = get_json("https://npm.ecosyste.ms/recent").first(200)
      rescue
        recent_names = []
      end
      (rss_names + recent_names).uniq
    end

    def fetch_package_metadata(name)
      get_json("#{@registry_url}/#{name.gsub('/', '%2F')}")
    rescue
      {}
    end

    def deprecation_info(name)
      versions = fetch_package_metadata(name)["versions"].values

      {
        is_deprecated: versions.all? { |v| v["deprecated"] },
        message: versions.last["deprecated"],
      }
    end

    def map_package_metadata(package)
      return false unless package && package["versions"].present?

      latest_version = package["versions"].to_a.last[1]
      
      h = {
        name: package["_id"],
        description: latest_version["description"].try(:delete, "\u0000"),
        homepage: homepage(package),
        keywords_array: Array.wrap(latest_version.fetch("keywords", [])).flatten,
        licenses: licenses(latest_version),
        repository_url: repository_url(package, latest_version),
        versions: package["versions"],
        time: package["time"],
        downloads_period: "last-month",
        namespace: namespace(package),
        metadata: {
          "funding" => latest_version["funding"],
          "dist-tags" => package["dist-tags"],
        }
      }

      downloads = downloads(package)
      h[:downloads] = downloads if downloads.present?

      h
    end

    def repository_url(package, latest_version)
      repo = latest_version.fetch("repository", {})
      repo = repo[0] if repo.is_a?(Array)
      repo_url = repo.try(:fetch, "url", nil)

      url = repo_fallback(repo_url, package["homepage"])
      return nil if url == "https://github.com/npm/security-holder"
      url
    end

    def homepage(package)
      return nil if package["homepage"] && package["homepage"].starts_with?("https://github.com/npm/security-holder")
      package["homepage"]
    end

    def namespace(package)
      return nil if package["_id"].split("/").length == 1
      package["_id"].split("/").first.gsub('@', '')
    end

    def downloads(package)
      get_json("https://api.npmjs.org/downloads/point/last-month/#{package["_id"]}")['downloads']
    rescue
      nil
    end

    def licenses(latest_version)
      license = latest_version.fetch("license", nil)
      if license.present?
        if license.is_a?(Hash)
          license.fetch("type", "")
        else
          license
        end
      else
        licenses = Array(latest_version.fetch("licenses", []))
        licenses.map do |lice|
          if lice.is_a?(Hash)
            lice.fetch("type", "")
          else
            lice
          end
        end.join(",")
      end
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      # npm license fields are supposed to be SPDX expressions now https://docs.npmjs.com/files/package.json#license
      pkg_metadata[:versions].reject{|k,v| existing_version_numbers.include?(k) }.map do |k, v|
        license = v.fetch("license", nil)
        license = licenses(v) unless license.is_a?(String)
        {
          number: k,
          published_at: pkg_metadata.fetch(:time, {}).fetch(k, nil),
          licenses: license,
          integrity: integrity(v),
          metadata: {
            deprecated: v["deprecated"],
          }
        }
      end
    end

    def integrity(version)
      dist = version.fetch("dist", {})
      dist.fetch("integrity", nil) || "sha1-"+dist.fetch("shasum", nil)
    rescue
      nil
    end

    def dependencies_metadata(_name, version, package)
      vers = package[:versions][version]
      return [] if vers.nil?

      map_dependencies(vers.fetch("dependencies", {}), "runtime") +
        map_dependencies(vers.fetch("devDependencies", {}), "Development") +
        map_dependencies(vers.fetch("optionalDependencies", {}), "Optional", true)
    end

    def maintainers_metadata(name)
      json = get_json("#{@registry_url}/#{name.gsub('/', '%2F')}")
      json['maintainers'].map do |user|
        {
          uuid: user["name"],
          login: user["name"],
          email: user["email"]
        }
      end
    rescue StandardError
      []
    end
  end
end
