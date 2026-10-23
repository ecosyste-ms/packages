# frozen_string_literal: true

module Ecosystem
  class Pecl < Base
    def self.purl_type
      "pecl"
    end

    def registry_url(package, version = nil)
      v = version.respond_to?(:number) ? version.number : version
      if v.present?
        "#{@registry_url}/package/#{package.name}/#{v}"
      else
        "#{@registry_url}/package/#{package.name}"
      end
    end

    def install_command(package, version = nil)
      v = version.respond_to?(:number) ? version.number : version
      "pecl install #{package.name}" + (v.present? ? "-#{v}" : "")
    end

    def download_url(package, version)
      v = version.respond_to?(:number) ? version.number : version
      return nil unless v.present?

      "#{@registry_url}/get/#{package.name}-#{v}.tgz"
    end

    def all_package_names
      xml = get_xml("#{@registry_url}/rest/p/packages.xml")
      xml.css("p").map(&:text).compact.uniq
    rescue StandardError => e
      Rails.logger.error "Pecl#all_package_names failed: #{e.message}"
      []
    end

    def recently_updated_package_names
      rss = get_raw("#{@registry_url}/feeds/latest.rss")
      xml = Nokogiri::XML(rss)
      xml.css("item title").map { |t| t.text.split(" ").first }.compact.uniq
    rescue StandardError => e
      Rails.logger.error "Pecl#recently_updated_package_names failed: #{e.message}"
      []
    end

    def fetch_package_metadata_uncached(name)
      info_url = "#{@registry_url}/rest/p/#{name.downcase}/info.xml"
      xml = get_xml(info_url)
      return nil if xml.nil? || xml.css("n").empty?

      package_name = xml.css("n").text.presence || name
      description = xml.css("d").text.presence || xml.css("s").text.presence
      license = xml.css("l").text.presence
      category = xml.css("ca").text.presence

      releases_url = "#{@registry_url}/rest/r/#{name.downcase}/allreleases.xml"
      releases_xml = get_xml(releases_url) rescue nil
      version_numbers = releases_xml.css("r v").map(&:text).compact.uniq rescue []

      {
        name: package_name,
        description: description,
        homepage: "#{@registry_url}/package/#{package_name}",
        licenses: license,
        repository_url: nil,
        keywords_array: [category].compact,
        versions: version_numbers
      }
    rescue StandardError => e
      Rails.logger.error "Pecl#fetch_package_metadata_uncached failed for #{name}: #{e.message}"
      nil
    end

    def map_package_metadata(package)
      return false if package.blank?

      package
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      versions_to_fetch = (pkg_metadata[:versions] || []).reject { |v| existing_version_numbers.include?(v) }.first(50)

      versions_to_fetch.map do |version_num|
        v_url = "#{@registry_url}/rest/r/#{pkg_metadata[:name].downcase}/#{version_num}.xml"
        v_xml = get_xml(v_url) rescue nil
        next if v_xml.nil?

        published_at_str = v_xml.css("da").text.presence
        published_at = Time.parse(published_at_str) rescue nil
        v_license = v_xml.css("l").text.presence || pkg_metadata[:licenses]
        v_summary = v_xml.css("s").text.presence
        v_desc = v_xml.css("d").text.presence
        download_url = v_xml.css("g").text.presence || "#{@registry_url}/get/#{pkg_metadata[:name]}-#{version_num}.tgz"

        {
          number: version_num,
          published_at: published_at,
          licenses: v_license,
          description: v_desc || v_summary,
          metadata: {
            state: v_xml.css("st").text.presence,
            notes: v_xml.css("n").text.presence,
            download_url: download_url
          }
        }
      end.compact
    end

    def maintainers_metadata(name)
      info_url = "#{@registry_url}/rest/p/#{name.downcase}/info.xml"
      xml = get_xml(info_url) rescue nil
      return [] if xml.nil?

      releases_url = "#{@registry_url}/rest/r/#{name.downcase}/allreleases.xml"
      releases_xml = get_xml(releases_url) rescue nil
      latest_version = releases_xml.css("r v").map(&:text).first rescue nil

      maintainers = []
      if latest_version.present?
        v_url = "#{@registry_url}/rest/r/#{name.downcase}/#{latest_version}.xml"
        v_xml = get_xml(v_url) rescue nil
        handle = v_xml.css("m").text.presence if v_xml
        if handle.present?
          maintainers << {
            login: handle,
            name: handle
          }
        end
      end
      maintainers
    rescue StandardError
      []
    end

    def maintainer_url(maintainer)
      login = maintainer.respond_to?(:login) ? maintainer.login : maintainer
      "#{@registry_url}/user/#{login}"
    end
  end
end
