# frozen_string_literal: true

module Ecosystem
  class Fdroid < Base

    def sync_in_batches?
      true
    end

    def has_dependent_repos?
      false
    end

    def self.purl_type
      'fdroid'
    end

    def registry_url(package, version = nil)
      "#{@registry_url}/packages/#{package.name}"
    end

    def download_url(package, version)
      return nil unless version.present?
      apk_name = version.metadata&.dig('apk_name')
      return nil unless apk_name
      "#{@registry_url}/repo/#{apk_name}"
    end

    def install_command(package, version = nil)
      "fdroidcl install #{package.name}"
    end

    def check_status(package)
      return "removed" if fetch_package_metadata(package.name).blank?
    end

    def index
      @index ||= get_json("#{@registry_url}/repo/index-v1.json")
    end

    def apps
      @apps ||= index['apps']
    end

    def apps_by_name
      @apps_by_name ||= apps.index_by { |a| a['packageName'] }
    end

    def version_packages
      @version_packages ||= index['packages']
    end

    def version_packages_for(name)
      version_packages[name] || []
    end

    def all_package_names
      apps.map { |a| a['packageName'] }
    rescue
      []
    end

    def recently_updated_package_names
      apps.sort_by { |a| a['lastUpdated'].to_i }.last(100).reverse.map { |a| a['packageName'] }
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      apps_by_name[name]
    end

    def localized_value(app, key)
      return nil unless app['localized'].is_a?(Hash)
      locale = app['localized']['en-US'] || app['localized']['en-GB'] || app['localized']['en'] || app['localized'].values.first
      locale&.dig(key)
    end

    def map_package_metadata(app)
      return false if app.blank? || app['packageName'].blank?

      description = app['description'] || localized_value(app, 'description')
      summary = app.dig('localized', 'en-US', 'summary') rescue nil
      summary ||= localized_value(app, 'summary')

      {
        name: app['packageName'],
        description: summary || description&.truncate(500),
        homepage: app['webSite'].presence || app['sourceCode'],
        licenses: app['license'],
        repository_url: repo_fallback(app['sourceCode'], app['webSite']),
        keywords_array: app['categories'],
        namespace: app['authorName'],
        metadata: {
          author_name: app['authorName'],
          author_email: app['authorEmail'],
          suggested_version_name: app['suggestedVersionName'],
          categories: app['categories'],
          anti_features: app['antiFeatures'],
          issue_tracker: app['issueTracker'],
          changelog: app['changelog'],
          donate: app['donate'],
          liberapay: app['liberapay'],
        }.compact
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkgs = version_packages_for(pkg_metadata[:name])
      pkgs.map do |v|
        {
          number: v['versionName'],
          published_at: v['added'] ? Time.at(v['added'] / 1000) : nil,
          integrity: "sha256-#{v['hash']}",
          metadata: {
            version_code: v['versionCode'],
            min_sdk_version: v['minSdkVersion'],
            target_sdk_version: v['targetSdkVersion'],
            max_sdk_version: v['maxSdkVersion'],
            size: v['size'],
            apk_name: v['apkName'],
            native_code: v['nativecode'],
          }.compact
        }
      end
    end
  end
end
