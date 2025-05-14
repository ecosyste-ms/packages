# frozen_string_literal: true
require "xmlrpc/client"

module Ecosystem
  class Pypi < Base

    PEP_508_NAME_REGEX = /[A-Z0-9][A-Z0-9._-]*[A-Z0-9]|[A-Z0-9]/i.freeze
    PEP_508_NAME_WITH_EXTRAS_REGEX = /(^#{PEP_508_NAME_REGEX}\s*(?:\[#{PEP_508_NAME_REGEX}(?:,\s*#{PEP_508_NAME_REGEX})*\])?)/i.freeze

    def purl(package, version = nil)
      PackageURL.new(
        type: purl_type,
        namespace: nil,
        name: package.name.downcase.gsub('_', '-'),
        version: version.try(:number).try(:encode,'iso-8859-1')
      ).to_s
    end


    def registry_url(package, version = nil)
      "#{@registry_url}/project/#{package.name}/#{version}"
    end

    def install_command(package, version = nil)
      "pip install #{package.name}" + (version ? "==#{version}" : "") + " --index-url #{@registry_url}/simple"
    end

    def documentation_url(package, version = nil)
      return package.metadata['documentation'] if package.metadata['documentation'].present?
      "https://#{package.name}.readthedocs.io/" + (version ? "en/#{version}" : "")
    end

    def download_url(_package, version)
      return nil unless version.present?
      version.metadata['download_url']
    end

    def all_package_names
      index = Nokogiri::HTML(get_raw("#{@registry_url}/simple/"))
      index.css("a").map(&:text).map(&:downcase)
    rescue
      []
    end

    def recently_updated_package_names
      u = "#{@registry_url}/rss/updates.xml"
      updated = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      u = "#{@registry_url}/rss/packages.xml"
      new_packages = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      (updated.map { |t| t.split(" ").first } + new_packages.map { |t| t.split(" ").first }).map(&:downcase).uniq
    rescue
      []
    end

    def fetch_package_metadata(name)
      get("#{@registry_url}/pypi/#{name}/json")
    rescue
      {}
    end

    def map_package_metadata(package)
      return false if package["info"].nil?
      h = {
        name: package["info"]["name"].downcase,
        description: package["info"]["summary"],
        homepage: (package["info"]["home_page"].presence || package.dig("info", "project_urls", "Homepage").presence || package.dig("info", "project_urls", "Home")),
        keywords_array: parse_keywords(package["info"]["keywords"]),
        licenses: licenses(package),
        repository_url: parse_repository_url(package),
        releases: package['releases'],
        downloads_period: 'last-month',
        metadata: {
          "funding" => package.dig("info", "project_urls", "Funding"),
          "documentation" => package.dig("info", "project_urls", "Documentation"),
          "classifiers" => package["info"]["classifiers"],
          "normalized_name" => package["info"]["name"].downcase.gsub('_', '-').gsub('.', '-')
        }
      }

      # TODO add more supported metadata from https://github.com/pypi/warehouse/blob/main/warehouse/templates/packaging/detail.html

      downloads = downloads(package)
      h[:downloads] = downloads if downloads.present?
      h
    end

    def parse_repository_url(package)
      repo_url = repo_fallback(find_repository_url(package.dig("info", "project_urls").try(:values)), package["info"]["home_page"])
      if repo_url.present?
        return repo_url
      else
        # try to parse from description
        description = package["info"]["description"].to_s
        package_name = package["info"]["name"].to_s.downcase
        if description.present?
          urls = URI.extract(description.gsub(/[\[\]]/, ' '), ['http', 'https']).map { |u| u.chomp('.') }

          matches = urls.map do |url|
            begin
              parsed = UrlParser.try_all(url)
              parsed if parsed&.include?(package_name)
            rescue
              nil
            end
          end.compact.group_by(&:itself).transform_values(&:count).sort_by { |k, v| -v }

          return matches[0][0] if matches.any?
        end
      end
    end

    def parse_keywords(keywords)
      return [] if keywords.blank?
      if keywords.include?(",")
        keywords.split(/\s*,\s*/).reject(&:blank?)
      else
        keywords.split(/\s+/).reject(&:blank?)
      end
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkg_metadata[:releases].map do |k, v|
        if v == []
          {
            number: k,
            published_at: nil,
            integrity: nil,
            metadata: {
              download_url: nil
            }
          }
        else
          {
            number: k,
            published_at: v[0]["upload_time"],
            integrity: 'sha256-' + v[0]['digests']['sha256'],
            metadata: {
              download_url: v[0]['url']
            }
          }
        end
      end
    end

    def parse_pep_508_dep_spec(dep)
      name, requirement = dep.split(PEP_508_NAME_WITH_EXTRAS_REGEX, 2).last(2)
      version, environment_markers = requirement.split(";").map(&:strip)

      # remove whitespace from name
      # remove parentheses surrounding version requirement
      [name.remove(/\s/), version&.remove(/[()]/) || "", environment_markers || ""]
    end

    def dependencies_metadata(name, version, _package)
      requires_dist = get_json("#{@registry_url}/pypi/#{name}/#{version}/json")["info"]["requires_dist"]
      return [] if requires_dist.nil?

      requires_dist.flat_map do |dep|
        name, version, environment_markers = parse_pep_508_dep_spec(dep)

        {
          package_name: name,
          requirements: version.presence || "*",
          kind: environment_markers.presence || "runtime",
          optional: environment_markers.present?,
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end

    def downloads(package)
      get_json("https://pypistats.org/api/packages/#{package["info"]["name"].downcase}/recent").fetch('data',{}).fetch('last_month')
    rescue
      nil
    end

    def licenses(package)
      return package["info"]["license"] if package["info"]["license"].present?

      license_classifiers = package["info"]["classifiers"].select { |c| c.start_with?("License :: ") }
      license_classifiers.map { |l| l.split(":: ").last }.join(",")
    end

    def package_find_names(package_name)
      [
        package_name,
        package_name.gsub("-", "_"),
        package_name.gsub("_", "-"),
      ]
    end
    
    def maintainers_metadata(name)
      server = XMLRPC::Client.new 'pypi.org', 'pypi', 80
      roles = server.call 'package_roles', name

      roles.map do |role, user|
        {
          uuid: user,
          login: user,
          role: role
        }
      end
    rescue StandardError
      fallback_maintainers_metadata(name)
    end

    def fallback_maintainers_metadata(name)
      url = "https://pypi.org/project/#{name}/"
      page = Nokogiri::HTML(get_raw(url))
      maintainers = page.css('.sidebar-section__maintainer a').map(&:text).map(&:strip)
      maintainers.map do |maintainer|
        {
          uuid: maintainer,
          login: maintainer
        }
      end
    rescue StandardError
      []
    end

    def maintainer_url(maintainer)
      "https://pypi.org/user/#{maintainer.login}/"
    end
  end
end
