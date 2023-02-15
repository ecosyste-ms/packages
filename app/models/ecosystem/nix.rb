# frozen_string_literal: true
module Ecosystem
  class Nix < Base

    # def purl(package, version = nil)
    #   PackageURL.new(
    #     type: 'apk',
    #     namespace: 'alpine',
    #     name: package.name.encode('iso-8859-1'),
    #     version: version.try(:number).try(:encode,'iso-8859-1'),
    #     qualifiers: { 'arch'=> package.metadata['architecture']},
    #   ).to_s
    # end

    # def registry_url(package, version = nil)
    #   "https://pkgs.alpinelinux.org/package/#{@registry.version}/#{package.metadata['repository']}/#{package.metadata['architecture']}/#{package.name}"
    # end

    # def download_url(package, version)
    #   "https://dl-cdn.alpinelinux.org/alpine/#{@registry.version}/#{package.metadata['repository']}/#{package.metadata['architecture']}/#{package.name}-#{version.number}.apk"
    # end

    # def install_command(package, version = nil)
    #   "apk add #{package.name}"
    # end

    def packages
      @packages ||= begin
        
        # branch = @registry.version 
        branch = '21.11'
        url = "https://channels.nixos.org/nixos-#{branch}/packages.json.br"
  
        Dir.mktmpdir do |dir|
          destination = "#{dir}/APKINDEX"
          `wget -P #{dir} #{url}`
          `brotli --decompress #{dir}/packages.json.br`
          return Oj.load(File.read("#{dir}/packages.json"))['packages']
        end
        
      end
    end

    def all_package_names
      packages.keys
    end

    def recently_updated_package_names
      # do the github rss thing on nixpkgs repo 
    end

    def fetch_package_metadata(name)
      packages[name]
    end

    def map_package_metadata(pkg_metadata)
      return false if pkg_metadata.blank? || pkg_metadata["P"].blank?
      # format: https://wiki.alpinelinux.org/wiki/Apk_spec
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
      return [] if data['m'].blank?
      d = data['m'].split('<')
      name = d[0].strip
      email = d[1].gsub('>','').strip
      [{
        uuid: email,
        name: name,
        url: "https://pkgs.alpinelinux.org/packages?maintainer=#{name}",
      }]
    end
  end
end
