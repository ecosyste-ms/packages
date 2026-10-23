# frozen_string_literal: true

module Ecosystem
  class Winget < Base
    def self.purl_type
      'winget'
    end

    def registry_url(package, _version = nil)
      "https://winstall.app/apps/#{package.name}"
    end

    def install_command(package, version = nil)
      v = version.respond_to?(:number) ? version.number : version
      if v.present?
        "winget install --id #{package.name} --version #{v}"
      else
        "winget install --id #{package.name}"
      end
    end

    def download_url(package, version = nil)
      return nil if version.blank?

      version.respond_to?(:download_url) ? version.download_url : nil
    end

    def check_status_url(package)
      "https://api.winstall.app/apps/#{package.name}"
    end

    def check_status(package)
      pkg = fetch_package_metadata(package.name)
      return nil if pkg.present? && pkg.is_a?(Hash) && (pkg['_id'].present? || pkg['name'].present?)

      url = check_status_url(package)
      response = Faraday.head(url)
      return 'removed' if [400, 404, 410].include?(response.status)
    rescue StandardError
      nil
    end

    def all_package_names
      names = []
      offset = 0
      limit = 1000
      total = nil

      loop do
        url = "https://api.winstall.app/apps?limit=#{limit}&offset=#{offset}"
        res = get_json(url)
        break if res.blank? || res['data'].blank?

        total ||= res['total']
        batch = res['data'].map { |item| item['_id'] }.compact
        break if batch.empty?

        names.concat(batch)
        offset += limit
        break if total && offset >= total
      end

      names.uniq
    rescue StandardError => e
      Rails.logger.error "Winget#all_package_names failed: #{e.message}"
      names.uniq
    end

    def recently_updated_package_names
      u = 'https://github.com/microsoft/winget-pkgs/commits/master.atom'
      rss = SimpleRSS.parse(get_raw(u))
      rss.items.map do |item|
        if item.title =~ /(?:New (?:version|package)|Update):\s+([^\s]+)\s+version/i
          $1
        elsif item.title =~ /([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)/
          $1
        end
      end.compact.uniq
    rescue StandardError => e
      Rails.logger.error "Winget#recently_updated_package_names failed: #{e.message}"
      []
    end

    def fetch_package_metadata_uncached(name)
      get_json("https://api.winstall.app/apps/#{name}")
    rescue StandardError => e
      Rails.logger.error "Winget#fetch_package_metadata_uncached failed for #{name}: #{e.message}"
      nil
    end

    def map_package_metadata(package)
      return false if package.blank?

      pkg_id = package['_id'] || package['name']
      return false if pkg_id.blank?

      {
        name: pkg_id,
        description: package['desc'].presence || package['fullDesc'],
        homepage: package['homepage'],
        repository_url: repo_fallback('', package['homepage']),
        licenses: package['license'],
        version: package['latestVersion'],
        updated_at: package['updatedAt'],
        keywords_array: (Array(package['tags']) + Array(package['categories'])).compact.uniq,
        versions: package['versions'] || [],
        metadata: {
          publisher: package['publisher'],
          moniker: package['moniker'],
          commands: package['commands'],
          license_url: package['licenseUrl'],
          release_notes_url: package['releaseNotesUrl'],
          author: package['author']
        }.compact
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      return [] if pkg_metadata[:versions].blank?

      Array(pkg_metadata[:versions]).map do |ver|
        v_num = ver.is_a?(Hash) ? ver['version'] : ver.to_s
        next if v_num.blank?

        download_url = ver.is_a?(Hash) ? Array(ver['installers']).first : nil
        {
          number: v_num,
          download_url: download_url,
          published_at: (Time.parse(pkg_metadata[:updated_at]) rescue nil)
        }
      end.compact
    end
  end
end
