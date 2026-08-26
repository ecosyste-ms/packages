# frozen_string_literal: true

require 'zlib'
require 'stringio'

module Ecosystem
  class Arch < Base

    def has_dependent_repos?
      false
    end

    def sync_maintainers_inline?
      true
    end

    def self.purl_type
      'alpm'
    end

    def self.purl_namespace_in_name?
      false
    end

    def aur?
      @registry.metadata&.dig('kind') == 'aur'
    end

    def purl_params(package, version = nil)
      qualifiers = {}
      qualifiers['arch'] = package.metadata['arch'] if package.metadata&.dig('arch').present?
      qualifiers['upstream'] = package.metadata['pkgbase'] if package.metadata&.dig('pkgbase').present?
      {
        type: 'alpm',
        namespace: 'arch',
        name: package.name.encode('iso-8859-1'),
        version: version.try(:number).try(:encode, 'iso-8859-1'),
        qualifiers: qualifiers.presence
      }
    end

    def registry_url(package, version = nil)
      if aur?
        "#{@registry_url}/packages/#{package.name}"
      else
        repo = package.metadata&.dig('repo') || 'extra'
        arch = package.metadata&.dig('arch') || 'x86_64'
        "#{@registry_url}/packages/#{repo}/#{arch}/#{package.name}/"
      end
    end

    def install_command(package, version = nil)
      aur? ? "yay -S #{package.name}" : "pacman -S #{package.name}"
    end

    def download_url(package, version)
      return nil unless version.present?
      if aur?
        urlpath = package.metadata&.dig('urlpath')
        urlpath.present? ? "#{@registry_url}#{urlpath}" : nil
      else
        repo = package.metadata&.dig('repo')
        filename = version.metadata&.dig('filename')
        return nil unless repo.present? && filename.present?
        "https://geo.mirror.pkgbuild.com/#{repo}/os/x86_64/#{filename}"
      end
    end

    def check_status_url(package)
      if aur?
        "#{@registry_url}/packages/#{package.name}"
      else
        "#{@registry_url}/packages/search/json/?name=#{package.name}"
      end
    end

    def check_status(package)
      data = fetch_package_metadata(package.name)
      "removed" if data.blank?
    end

    def all_package_names
      aur? ? aur_all_package_names : official_all_package_names
    rescue
      []
    end

    def recently_updated_package_names
      aur? ? aur_recently_updated_package_names : official_recently_updated_package_names
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      results = if aur?
        get_json("#{@registry_url}/rpc/v5/info?arg[]=#{CGI.escape(name)}")['results']
      else
        get_json("#{@registry_url}/packages/search/json/?name=#{CGI.escape(name)}")['results']
      end
      return nil if results.blank?
      pick_result(results)
    rescue
      nil
    end

    def map_package_metadata(pkg)
      return false if pkg.blank?
      aur? ? map_aur(pkg) : map_official(pkg)
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      [pkg_metadata[:version_data]].compact
    end

    def dependencies_metadata(_name, version, pkg_metadata)
      return [] unless version == pkg_metadata.dig(:version_data, :number)
      pkg_metadata[:dependencies] || []
    end

    def maintainers_metadata(name)
      pkg = fetch_package_metadata(name)
      return [] if pkg.blank?
      logins = aur? ? [pkg['Maintainer'], *Array(pkg['CoMaintainers'])].compact : Array(pkg['maintainers'])
      logins.uniq.map do |login|
        {
          uuid: login,
          login: login,
          url: maintainer_url_for(login),
        }
      end
    end

    def maintainer_url(maintainer)
      maintainer_url_for(maintainer.login)
    end

    def maintainer_url_for(login)
      if aur?
        "#{@registry_url}/account/#{login}"
      else
        "#{@registry_url}/packages/?maintainer=#{login}"
      end
    end

    def official_all_package_names
      page = 1
      names = []
      loop do
        data = get_json("#{@registry_url}/packages/search/json/?page=#{page}")
        names.concat(data['results'].map { |r| r['pkgname'] })
        break if page >= data['num_pages'].to_i
        page += 1
      end
      names.uniq
    end

    def official_recently_updated_package_names
      rss = SimpleRSS.parse(get_raw("#{@registry_url}/feeds/packages/"))
      rss.items.map { |i| i.link.chomp('/').split('/').last }.compact.uniq
    end

    def aur_all_package_names
      body = get_raw("#{@registry_url}/packages.gz")
      body = Zlib::GzipReader.new(StringIO.new(body)).read if body.bytes.first(2) == [0x1f, 0x8b]
      body.lines.map(&:strip).reject { |l| l.blank? || l.start_with?('#') }
    end

    def aur_recently_updated_package_names
      %w[/rss/modified /rss/].flat_map do |path|
        doc = Nokogiri::XML(get_raw("#{@registry_url}#{path}"))
        doc.css('item > title').map(&:text).map(&:strip)
      end.compact.uniq
    end

    def pick_result(results)
      return results.first if results.length == 1
      results.find { |r| !r['repo'].to_s.include?('testing') } || results.first
    end

    def map_official(pkg)
      version = build_version(pkg['epoch'], pkg['pkgver'], pkg['pkgrel'])
      {
        name: pkg['pkgname'],
        description: pkg['pkgdesc'],
        homepage: pkg['url'],
        licenses: Array(pkg['licenses']).join(' AND ').presence,
        repository_url: repo_fallback(nil, pkg['url']),
        keywords_array: Array(pkg['groups']),
        namespace: pkg['repo'],
        dependencies: map_arch_dependencies(pkg, %w[depends makedepends checkdepends optdepends]),
        version_data: {
          number: version,
          published_at: pkg['build_date'],
          metadata: {
            arch: pkg['arch'],
            filename: pkg['filename'],
            compressed_size: pkg['compressed_size'],
            installed_size: pkg['installed_size'],
            packager: pkg['packager'],
          }.compact
        },
        metadata: {
          repo: pkg['repo'],
          arch: pkg['arch'],
          pkgbase: pkg['pkgbase'],
          packaging_repository_url: "https://gitlab.archlinux.org/archlinux/packaging/packages/#{pkg['pkgbase']}",
          flag_date: pkg['flag_date'],
          provides: pkg['provides'],
          replaces: pkg['replaces'],
          conflicts: pkg['conflicts'],
        }.compact
      }
    end

    def map_aur(pkg)
      {
        name: pkg['Name'],
        description: pkg['Description'],
        homepage: pkg['URL'],
        licenses: Array(pkg['License']).join(' AND ').presence,
        repository_url: repo_fallback(nil, pkg['URL']),
        keywords_array: Array(pkg['Keywords']),
        namespace: pkg['Maintainer'],
        dependencies: map_arch_dependencies(pkg, %w[Depends MakeDepends CheckDepends OptDepends]),
        version_data: {
          number: pkg['Version'],
          published_at: pkg['LastModified'].present? ? Time.at(pkg['LastModified'].to_i) : nil,
          metadata: {
            first_submitted: pkg['FirstSubmitted'].present? ? Time.at(pkg['FirstSubmitted'].to_i) : nil,
          }.compact
        },
        metadata: {
          pkgbase: pkg['PackageBase'],
          urlpath: pkg['URLPath'],
          packaging_repository_url: "https://aur.archlinux.org/#{pkg['PackageBase']}.git",
          num_votes: pkg['NumVotes'],
          popularity: pkg['Popularity'],
          out_of_date: pkg['OutOfDate'],
          submitter: pkg['Submitter'],
        }.compact
      }
    end

    def build_version(epoch, pkgver, pkgrel)
      v = pkgver.to_s
      v = "#{v}-#{pkgrel}" if pkgrel.present?
      v = "#{epoch}:#{v}" if epoch.to_i > 0
      v
    end

    DEP_KIND = {
      'depends' => 'runtime', 'makedepends' => 'build', 'checkdepends' => 'test', 'optdepends' => 'optional',
      'Depends' => 'runtime', 'MakeDepends' => 'build', 'CheckDepends' => 'test', 'OptDepends' => 'optional',
    }.freeze

    def map_arch_dependencies(pkg, keys)
      keys.flat_map do |key|
        Array(pkg[key]).map { |d| parse_dependency(d, DEP_KIND[key]) }
      end.compact
    end

    def parse_dependency(str, kind)
      name_part = str.split(':', 2).first.strip
      m = name_part.match(/\A([^<>=]+)(.*)\z/)
      return nil unless m && m[1].present?
      {
        package_name: m[1].strip,
        requirements: m[2].strip.presence || '*',
        kind: kind,
        optional: kind == 'optional',
        ecosystem: 'arch',
      }
    end
  end
end
