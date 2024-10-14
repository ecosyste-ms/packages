# frozen_string_literal: true
module Ecosystem
  class Ubuntu < Base
    def sync_in_batches?
      true
    end

    def docker_usage_path(package)
      "deb/#{package.ecosystem}/#{package.name}"
    end

    def purl(package, version = nil)
      PackageURL.new(
        type: 'deb',
        namespace: 'ubuntu',
        name: package.name.encode('iso-8859-1'),
        version: version.try(:number).try(:encode,'iso-8859-1'),
        qualifiers: { 'arch'=> package.metadata['architecture'], 'distro': "ubuntu-#{@registry.version}"},
      ).to_s
    end

    def registry_url(package, version = nil)
      "https://launchpad.net/ubuntu/+source/#{package.name}/#{version.try(:number)}"
    end

    def download_url(package, version)
      "http://ftp.ubuntu.com/ubuntu/pool/main/#{package.name[0]}/#{package.name}/#{package.name}_#{version.number}.tar.xz"
    end

    def check_status(package)
      return "removed" if fetch_package_metadata(package.name).blank?
    end

    def install_command(package, version = nil)
      "apt-get install #{package.name}"
    end

    def fetch_packages
      components = ['main', 'universe', 'multiverse', 'restricted']
      packages = []
      components.each do |component|
        url = "http://ftp.ubuntu.com/ubuntu/dists/#{@registry.metadata['codename']}/#{component}/source/Sources.gz"
        puts url
        response = Faraday.get(url)
        sources = Zlib::GzipReader.new(StringIO.new(response.body)).read
        if response.status == 200
          packages += sources.split("\n\n")
        else
          puts "Error: #{response.status}"
        end
      end
      packages
    end
 
    def packages
      @packages ||= fetch_packages.map do |source|
        lines = source.split("\n")
        key_value_pairs = lines.map{|l| l.split(': ') }.reject{|k,v| v.blank? }.to_h
        {
          name: key_value_pairs['Package'],
          version: key_value_pairs['Version'],
          homepage: key_value_pairs['Homepage'],
          repository_url: key_value_pairs['Vcs-Browser'],
          keywords: key_value_pairs['Section'].split(', '),
          metadata: {
            component: key_value_pairs['Directory'].split('/').second,
            architecture: key_value_pairs['Architecture'],
            priority: key_value_pairs['Priority'],
            binary: key_value_pairs['Binary'],
            standards_version: key_value_pairs['Standards-Version'],
          },
          properties: key_value_pairs
        }
      end
    end

    def all_package_names
      packages.map{|p| p[:name] }
    end

    def recently_updated_package_names
      # TODO
    end

    def fetch_package_metadata(name)
      # TODO load the control file from the download_url in debian directory for the description (also maybe the copyright file)
      packages.find{|p| p[:name] == name }
    end

    def map_package_metadata(pkg_metadata)
      pkg_metadata
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      # TODO fetch publish time from html on http://ftp.ubuntu.com/ubuntu/pool/#{component}/#{firstletter}/#{name}/
      [{
        number: pkg_metadata[:version]
      }]
    end

    def dependencies_metadata(name, version, pkg_metadata)
      # TODO
      kinds = %w{ Depends, Recommends, Suggests, Pre-Depends, Build-Depends, Build-Depends-Indep, Build-Depends-Arch }
      kinds.map do |kind|
        pkg_metadata[:properties][kind].split(', ').map do |dep|
          name = dep.split(' ').first
          if dep.split(' ').length > 1
            requirements = dep.split(' ').last
            requirements = requirements.gsub('(', '').gsub(')', '').strip
          else
            requirements = '*'
          end
          {
            package_name: dep,
            ecosystem: 'ubuntu',
            kind: kind,
            requirements: requirements,
            optional: ['Recommends', 'Suggests'].include?(kind)
          }
        end
      end.flatten
    end

    def maintainers_metadata(name)
      # TODO
      package = fetch_package_metadata(name)
      return [] if package[:properties]['Maintainer'].blank?
      d = package[:properties]['Maintainer'].split('<')
      name = d[0].strip
      email = d[1].gsub('>','').strip
      [{
        uuid: email,
        name: name
      }]
    end
  end
end