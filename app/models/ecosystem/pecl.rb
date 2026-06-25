# frozen_string_literal: true

module Ecosystem
  class Pecl < Base
    def registry_url(package, version = nil)
      if version
        "https://pecl.php.net/package/#{package.name}/#{version.number}"
      else
        "https://pecl.php.net/package/#{package.name}"
      end
    end

    def install_command(package, version = nil)
      "pecl install #{package.name}" + (version ? "-#{version}" : "")
    end

    def check_status_url(package)
      "https://pecl.php.net/rest/p/#{package.name.downcase}/info.xml"
    end

    def all_package_names
      packages = get_xml("#{registry_url_base}/rest/p/packages.xml")
      packages.xpath("//*[local-name()='p']").map(&:text).reject(&:blank?)
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      info = get_xml("#{registry_url_base}/rest/p/#{name.downcase}/info.xml")
      releases = get_xml("#{registry_url_base}/rest/r/#{name.downcase}/allreleases.xml")
      {
        info: info,
        releases: releases
      }
    rescue
      {}
    end

    def map_package_metadata(package)
      info = package[:info]
      return nil if info.blank?

      name = xml_text(info, "n")
      return nil if name.blank?

      {
        name: name,
        description: xml_text(info, "s"),
        homepage: "https://pecl.php.net/package/#{name}",
        repository_url: nil,
        licenses: xml_text(info, "l"),
        metadata: {
          category: xml_text(info, "ca"),
          summary: xml_text(info, "s"),
          description: xml_text(info, "d")
        }
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      releases = pkg_metadata[:releases]
      return [] if releases.blank?

      releases.xpath("//*[local-name()='r']").map do |release|
        version = xml_text(release, "v")
        next if version.blank?

        details = fetch_release_metadata(pkg_metadata[:name], version)
        {
          number: version,
          published_at: details[:published_at],
          metadata: {
            status: xml_text(release, "s"),
            license: details[:license],
            summary: details[:summary],
            description: details[:description],
            notes: details[:notes]
          }.compact
        }
      end.compact
    end

    def purl_type
      "pear"
    end

    private

    def registry_url_base
      registry_url.to_s.delete_suffix("/")
    end

    def xml_text(document, name)
      document.at_xpath(".//*[local-name()='#{name}']")&.text
    end

    def fetch_release_metadata(name, version)
      release = get_xml("#{registry_url_base}/rest/r/#{name.downcase}/#{version}.xml")
      {
        published_at: xml_text(release, "da"),
        license: xml_text(release, "l"),
        summary: xml_text(release, "s"),
        description: xml_text(release, "d"),
        notes: xml_text(release, "n")
      }
    rescue
      {}
    end
  end
end
