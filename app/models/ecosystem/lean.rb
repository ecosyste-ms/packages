# frozen_string_literal: true

module Ecosystem
  class Lean < Base

    def sync_in_batches?
      true
    end

    def purl_params(package, version = nil)
      {
        type: purl_type,
        namespace: package.name.split('/').first,
        name: package.name.split('/').last,
        version: version.try(:number).try(:encode, 'iso-8859-1', invalid: :replace, undef: :replace, replace: '')
      }
    end

    def registry_url(package, _version = nil)
      owner, name = package.name.split('/', 2)
      "#{@registry_url}/@#{owner}/#{name}"
    end

    def download_url(package, version = nil)
      return nil if package.repository_url.blank?
      return nil unless package.repository_url.include?('/github.com/')
      full_name = package.repository_url.gsub('https://github.com/', '').gsub(/\.git$/, '')
      if version.present?
        "https://codeload.github.com/#{full_name}/tar.gz/#{version.number}"
      else
        branch = package.metadata&.dig('default_branch') || 'main'
        "https://codeload.github.com/#{full_name}/tar.gz/refs/heads/#{branch}"
      end
    end

    def check_status(package)
      return "removed" if fetch_package_metadata(package.name).blank?
    end

    def manifest
      @manifest ||= get_json("#{@registry_url}/index/manifest.json")
    end

    def packages
      @packages ||= manifest['packages'].index_by { |p| p['fullName'] }
    rescue
      {}
    end

    def all_package_names
      packages.keys
    end

    def recently_updated_package_names
      packages.values.sort_by { |p| p['updatedAt'].to_s }.last(100).reverse.map { |p| p['fullName'] }
    rescue
      []
    end

    def namespace_package_names(namespace)
      packages.values.select { |p| p['owner'] == namespace }.map { |p| p['fullName'] }
    end

    def fetch_package_metadata_uncached(name)
      packages[name]
    end

    def map_package_metadata(pkg)
      return false if pkg.blank? || pkg['fullName'].blank?

      source = Array(pkg['sources']).first || {}
      repo_url = source['repoUrl'] || source['gitUrl']

      {
        name: pkg['fullName'],
        description: pkg['description'],
        homepage: pkg['homepage'],
        licenses: pkg['license'],
        keywords_array: pkg['keywords'],
        repository_url: repo_fallback(repo_url, pkg['homepage']),
        namespace: pkg['owner'],
        versions: pkg['versions'],
        metadata: {
          stars: pkg['stars'],
          created_at: pkg['createdAt'],
          updated_at: pkg['updatedAt'],
          default_branch: source['defaultBranch'],
          git_url: source['gitUrl'],
        }.compact
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      versions = pkg_metadata[:versions] || []
      versions.uniq { |v| v['revision'] }.map do |v|
        {
          number: v['revision'],
          published_at: v['date'],
          licenses: v['license'],
          metadata: {
            version: v['version'],
            tag: v['tag'],
            toolchain: v['toolchain'],
            platform_independent: v['platformIndependent'],
          }.compact
        }
      end
    end

    def dependencies_metadata(_name, version, pkg_metadata)
      versions = pkg_metadata[:versions] || []
      ver = versions.find { |v| v['revision'] == version }
      return [] unless ver
      Array(ver['dependencies']).reject { |d| d['transitive'] }.map do |dep|
        package_name = dep['fullName'].presence || [dep['scope'], dep['name']].compact.join('/')
        next if package_name.blank?
        {
          package_name: package_name,
          requirements: dep['inputRev'].presence || dep['rev'].presence || dep['version'].presence || '*',
          kind: 'runtime',
          ecosystem: self.class.name.demodulize.downcase
        }
      end.compact
    end
  end
end
