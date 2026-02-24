# frozen_string_literal: true

module Ecosystem
  class Ctan < Base

    SPDX_MAP = {
      'lppl1.3c' => 'LPPL-1.3c',
      'lppl1.3a' => 'LPPL-1.3a',
      'lppl1.3' => 'LPPL-1.3a',
      'lppl1.2' => 'LPPL-1.2',
      'lppl1' => 'LPPL-1.0',
      'lppl' => 'LPPL-1.0',
      'gpl' => 'GPL-2.0-or-later',
      'gpl2' => 'GPL-2.0-only',
      'gpl2+' => 'GPL-2.0-or-later',
      'gpl3' => 'GPL-3.0-only',
      'gpl3+' => 'GPL-3.0-or-later',
      'lgpl' => 'LGPL-2.1-or-later',
      'lgpl2.1' => 'LGPL-2.1-only',
      'lgpl3' => 'LGPL-3.0-only',
      'agpl3' => 'AGPL-3.0-only',
      'bsd' => 'BSD-2-Clause',
      'bsd2' => 'BSD-2-Clause',
      'bsd3' => 'BSD-3-Clause',
      'bsd4' => 'BSD-4-Clause',
      'mit' => 'MIT',
      'apache2' => 'Apache-2.0',
      'cc-by-4' => 'CC-BY-4.0',
      'cc-by-sa-4' => 'CC-BY-SA-4.0',
      'cc-by-nc-4' => 'CC-BY-NC-4.0',
      'cc-by-nc-sa-4' => 'CC-BY-NC-SA-4.0',
      'cc-by-3' => 'CC-BY-3.0',
      'cc-by-sa-3' => 'CC-BY-SA-3.0',
      'cc0' => 'CC0-1.0',
      'ofl' => 'OFL-1.1',
      'pd' => 'Public Domain',
      'fdl' => 'GFDL-1.3-or-later',
      'isc' => 'ISC',
      'artistic' => 'Artistic-1.0',
      'artistic2' => 'Artistic-2.0',
    }.freeze

    def registry_url(package, _version = nil)
      "https://ctan.org/pkg/#{package.name}"
    end

    def download_url(package, _version = nil)
      ctan_path = package.metadata&.dig('ctan_path')
      return nil unless ctan_path.present?
      "https://mirrors.ctan.org#{ctan_path}.zip"
    end

    def install_command(package, _version = nil)
      "tlmgr install #{package.name}"
    end

    def check_status(package)
      pkg = fetch_package_metadata(package.name)
      return nil if pkg.present? && pkg.is_a?(Hash) && pkg["id"].present?

      url = check_status_url(package)
      response = Faraday.head(url)
      return "removed" if [400, 404, 410].include?(response.status)
    end

    def all_package_names
      get("https://ctan.org/json/2.0/packages").map { |p| p["key"] }.uniq
    rescue
      []
    end

    def recently_updated_package_names
      u = "https://ctan.org/ctan-ann/rss"
      titles = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      titles.map { |t| t.split(": ").last }.uniq
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      get("https://ctan.org/json/2.0/pkg/#{name}")
    rescue
      {}
    end

    def map_package_metadata(package)
      return false unless package.present?

      description = package.dig("descriptions", 0, "text")
      description = Rails::Html::FullSanitizer.new.sanitize(description).squish if description.present?
      description = package["caption"] if description.blank?

      license_field = package["license"]
      licenses = Array(license_field).map { |l| SPDX_MAP[l] || l }.join(" and ")

      {
        name: package["id"],
        description: description,
        licenses: licenses.presence,
        repository_url: repo_fallback(package["repository"].to_s, ""),
        keywords_array: package["topics"],
        metadata: {
          'ctan_path' => package.dig("ctan", "path"),
          'texlive' => package["texlive"],
          'miktex' => package["miktex"],
          'version_number' => package.dig("version", "number"),
          'version_date' => package.dig("version", "date"),
        }
      }
    end

    def versions_metadata(pkg_metadata, _existing_version_numbers = [])
      number = pkg_metadata.dig(:metadata, 'version_number')
      date = pkg_metadata.dig(:metadata, 'version_date')
      return [] if number.blank?

      [
        {
          number: number,
          published_at: date,
        },
      ]
    end

    def maintainers_metadata(name)
      pkg = fetch_package_metadata(name)
      return [] unless pkg.present? && pkg["authors"].present?

      pkg["authors"].select { |a| a["active"] }.map do |author|
        author_data = get("https://ctan.org/json/2.0/author/#{author['id']}")
        name_parts = [author_data["givenname"], author_data["von"], author_data["familyname"]].select(&:present?)
        {
          uuid: author["id"],
          name: name_parts.any? ? name_parts.join(" ") : (author_data["pseudonym"] || author["id"]),
        }
      end
    rescue StandardError
      []
    end
  end
end
