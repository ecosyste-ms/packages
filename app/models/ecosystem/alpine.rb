# frozen_string_literal: true
module Ecosystem
  class Alpine < Base

    def sync_in_batches?
      true
    end

    def purl(package, version = nil)
      PackageURL.new(
        type: 'apk',
        namespace: 'alpine',
        name: package.name.encode('iso-8859-1'),
        version: version.try(:number).try(:encode,'iso-8859-1'),
        qualifiers: { 'arch'=> package.metadata['architecture']},
      ).to_s
    end

    def registry_url(package, version = nil)
      "https://pkgs.alpinelinux.org/package/#{@registry.version}/#{package.metadata['repository']}/#{package.metadata['architecture']}/#{package.name}"
    end

    def download_url(package, version)
      "https://dl-cdn.alpinelinux.org/alpine/#{@registry.version}/#{package.metadata['repository']}/#{package.metadata['architecture']}/#{package.name}-#{version.number}.apk"
    end

    def install_command(package, version = nil)
      "apk add #{package.name}"
    end

    def check_status(package)
      return "removed" if fetch_package_metadata(package.name).blank?
    end

    def fetch_packages(repository, architecture)
      version = @registry.version
      url = "https://dl-cdn.alpinelinux.org/alpine/#{version}/#{repository}/#{architecture}/APKINDEX.tar.gz"

      packages = []
      package = {'r' => repository}

      Dir.mktmpdir do |dir|

        destination = "#{dir}/APKINDEX"
        `wget -P #{dir} #{url}`
        `tar -xzf #{dir}/APKINDEX.tar.gz -C #{dir}`
        
        File.foreach(destination) do |line|
          if line.blank?
            packages << package
            package = {'r' => repository}
          end
          key = line.split(':')[0]
          value = line.split(':')[1..-1].join(':').strip
          package[key] = value if key.present?
        end
        packages << package if package['P'].present?
      end
      packages
    end
 
    def packages
      @packages ||= begin
        
        # TODO architectures ['x86_64', 'x86', 'aarch64', 'armhf', 'ppc64le', 's390x', 'armv7', 'riscv64']
        
        main_packages = fetch_packages('main', 'x86_64')
        community_packages = fetch_packages('community', 'x86_64')

        if @registry.version == 'edge'
          testing_packages = fetch_packages('testing', 'x86_64')
          main_packages + community_packages + testing_packages
        else
          main_packages + community_packages
        end
        
      end
    end

    def all_package_names
      packages.map{|p| p['P'] }
    end

    def recently_updated_package_names
      packages.sort_by{|p| p['t']}.reverse.map{|p| p['P'] }.first(100)
    end

    def fetch_package_metadata(name)
      packages.find{|p| p['P'] == name }
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

    def maintainer_url(maintainer)
      "https://pkgs.alpinelinux.org/packages?maintainer=#{maintainer.name}"
    end
  end
end
