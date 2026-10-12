# frozen_string_literal: true

module Ecosystem
  class Chocolatey < Base

    def has_dependent_repos?
      false
    end

    def self.purl_type
      'chocolatey'
    end

    def registry_url(package, version = nil)
      "#{@registry_url}/packages/#{package.name}#{"/#{version}" if version.present?}"
    end

    def download_url(package, version)
      return nil unless version.present?
      "#{@registry_url}/api/v2/package/#{package.name}/#{version}"
    end

    def install_command(package, version = nil)
      "choco install #{package.name}#{" --version=#{version}" if version.present?}"
    end

    def documentation_url(package, version = nil)
      package.metadata&.dig('docs_url').presence
    end

    def check_status_url(package)
      "#{@registry_url}/api/v2/FindPackagesById()?id='#{package.name}'&$top=1"
    end

    def check_status(package)
      doc = get_xml(check_status_url(package))
      doc.remove_namespaces!
      "removed" if doc.css('entry').empty?
    rescue
      nil
    end

    def all_package_names
      names = []
      url = "#{@registry_url}/api/v2/Packages()?$filter=IsLatestVersion&$select=Id"
      while url.present?
        doc = get_xml(url)
        doc.remove_namespaces!
        names.concat(doc.css('entry > title').map(&:text))
        url = doc.at_css('link[rel="next"]')&.[]('href')
      end
      names.uniq
    rescue
      names.uniq
    end

    def recently_updated_package_names
      doc = get_xml('https://feeds.feedburner.com/chocolatey')
      doc.remove_namespaces!
      doc.css('entry, item').map do |item|
        link = item.at_css('link')&.[]('href') || item.at_css('link')&.text
        link.to_s.split('/packages/').last.to_s.split('/').first
      end.compact.reject(&:blank?).uniq
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      entries = []
      url = "#{@registry_url}/api/v2/FindPackagesById()?id='#{CGI.escape(name)}'"
      while url.present?
        doc = get_xml(url)
        doc.remove_namespaces!
        page = doc.css('entry').map { |e| entry_to_hash(e) }
        break if page.empty?
        entries.concat(page)
        url = doc.at_css('link[rel="next"]')&.[]('href')
      end
      return nil if entries.empty?
      { 'name' => name, 'entries' => entries }
    rescue
      nil
    end

    def entry_to_hash(entry)
      h = {}
      entry.css('properties > *').each { |p| h[p.name] = p.text }
      h['Id'] = entry.at_css('title')&.text
      h['Authors'] = entry.at_css('author name')&.text
      h['ContentSrc'] = entry.at_css('content')&.[]('src')
      h
    end

    def map_package_metadata(pkg)
      return false if pkg.blank? || pkg['entries'].blank?

      latest = pkg['entries'].find { |e| e['IsLatestVersion'] == 'true' } ||
               pkg['entries'].find { |e| e['IsAbsoluteLatestVersion'] == 'true' } ||
               pkg['entries'].last

      {
        name: pkg['name'],
        description: latest['Description']&.truncate(1000),
        homepage: latest['ProjectUrl'].presence,
        repository_url: repo_fallback(latest['ProjectSourceUrl'], latest['ProjectUrl']),
        keywords_array: latest['Tags'].to_s.split(/\s+/).reject(&:blank?),
        licenses: latest['LicenseUrl'].presence,
        downloads: pkg['entries'].map { |e| e['DownloadCount'].to_i }.max,
        downloads_period: 'total',
        namespace: latest['Authors'].presence,
        entries: pkg['entries'],
        metadata: {
          title: latest['Title'],
          authors: latest['Authors'],
          icon_url: latest['IconUrl'].presence,
          docs_url: latest['DocsUrl'].presence,
          bug_tracker_url: latest['BugTrackerUrl'].presence,
          mailing_list_url: latest['MailingListUrl'].presence,
          package_source_url: latest['PackageSourceUrl'].presence,
          is_approved: latest['IsApproved'] == 'true',
          package_status: latest['PackageStatus'].presence,
        }.compact
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      Array(pkg_metadata[:entries]).map do |e|
        next if e['Version'].blank?
        {
          number: e['Version'],
          published_at: e['Published'].presence || e['Created'].presence,
          integrity: integrity(e),
          status: e['PackageStatus'] == 'Unlisted' ? 'unlisted' : nil,
          metadata: {
            downloads: e['VersionDownloadCount'].to_i,
            package_size: e['PackageSize'].to_i,
            is_prerelease: e['IsPrerelease'] == 'true',
            package_status: e['PackageStatus'].presence,
            content_src: e['ContentSrc'],
            dependencies: e['Dependencies'].presence,
          }.compact
        }
      end.compact
    end

    def dependencies_metadata(_name, version, pkg_metadata)
      entry = Array(pkg_metadata[:entries]).find { |e| e['Version'] == version }
      return [] if entry.nil?
      parse_dependencies(entry['Dependencies'])
    end

    def parse_dependencies(str)
      return [] if str.blank?
      str.split('|').map do |dep|
        name, range, _framework = dep.split(':', 3)
        next if name.blank?
        {
          package_name: name,
          requirements: range.presence || '*',
          kind: 'runtime',
          ecosystem: 'chocolatey',
        }
      end.compact
    end

    def integrity(entry)
      return nil if entry['PackageHash'].blank?
      algo = entry['PackageHashAlgorithm'].to_s.downcase.presence || 'sha512'
      "#{algo}-#{entry['PackageHash']}"
    end
  end
end
