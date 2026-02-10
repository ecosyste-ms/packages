# frozen_string_literal: true
module Ecosystem
  class Postmarketos < Base

    def sync_in_batches?
      true
    end

    def sync_maintainers_inline?
      true
    end

    def has_dependent_repos?
      false
    end

    def purl_params(package, version = nil)
      {
        type: 'apk',
        namespace: 'postmarketos',
        name: package.name.encode('iso-8859-1'),
        version: version.try(:number).try(:encode,'iso-8859-1'),
        qualifiers: { 'arch' => package.metadata['architecture'] }
      }
    end

    def registry_url(package, version = nil)
      "https://pkgs.postmarketos.org/package/#{@registry.version}/postmarketos/#{package.metadata['architecture']}/#{package.name}"
    end

    def download_url(package, version)
      "https://mirror.postmarketos.org/postmarketos/#{@registry.version}/#{package.metadata['architecture']}/#{package.name}-#{version.number}.apk"
    end

    def check_status(package)
      return "removed" if fetch_package_metadata(package.name).blank?
    end

    def install_command(package, version = nil)
      "apk add #{package.name}"
    end

    def fetch_packages(architecture)
      version = @registry.version
      url = "https://mirror.postmarketos.org/postmarketos/#{version}/#{architecture}/APKINDEX.tar.gz"
      cache_key = "postmarketos-#{version}-#{architecture}"
      cached_file = download_and_cache(url, cache_key)
      parse_apkindex(cached_file)
    end
 
    def packages
      @packages ||= begin
        
        # TODO architectures ['x86_64', 'armv7', 'aarch64']
        
        fetch_packages('x86_64')
        
      end
    end

    def all_package_names
      packages.map{|p| p['P'] }
    end

    def recently_updated_package_names
      packages.sort_by{|p| p['t']}.reverse.map{|p| p['P'] }.first(100)
    end

    def fetch_package_metadata_uncached(name)
      packages.find{|p| p['P'] == name }
    end

    def map_package_metadata(pkg_metadata)
      return false if pkg_metadata.blank? || pkg_metadata["P"].blank?
      # format: https://wiki.postmarketoslinux.org/wiki/Apk_spec
      {
        name: pkg_metadata["P"],
        description: pkg_metadata["T"],
        homepage: pkg_metadata["U"],
        licenses: pkg_metadata["L"],
        repository_url: repo_fallback(pkg_metadata["U"], pkg_metadata["U"]),
        namespace: pkg_metadata["r"],
        metadata: {
          repository: pkg_metadata["r"],
          architecture: pkg_metadata['A'],
        }
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      data = fetch_package_metadata(pkg_metadata[:name])
      return [] if data.blank?
      [
        {
          number: data['V'],
          published_at: Time.at(data['t'].to_i),
          licenses: data['L'],
          integrity: data['C'],
          metadata: {
            architecture: data['A'],
            size: data['S'],
            installed_size: data['I'],
            checksum: data['C'],
            commit: data['c'],
            origin: data['o'],
            provides: data['p'],
            install_if: data['i'],
          }
        }
      ]
    end

    def dependencies_metadata(name, version, pkg_metadata)
      data = fetch_package_metadata(name)
      return [] if data.blank? || data['D'].blank?
      deps = data['D'].split(' ').map{|dep| packages.select{|pkg| pkg['p']&& pkg['p'].include?(dep)}.first || packages.select{|pkg| pkg['P'] == dep}.first  }.uniq
      deps.map do |dep|
        {
          package_name: dep['P'],
          requirements: '*',
          kind: 'install',
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end

    def maintainers_metadata(name)
      data = fetch_package_metadata(name)
      return [] if data.blank? || data['m'].blank?
      d = data['m'].split('<')
      name = d[0].strip
      email = d[1].gsub('>','').strip
      [{
        uuid: email,
        name: name,
        url: "https://pkgs.postmarketoslinux.org/packages?maintainer=#{name}",
      }]
    end
    
    def maintainer_url(maintainer)
      "https://pkgs.postmarketoslinux.org/packages?maintainer=#{maintainer.name}"
    end
  end
end
