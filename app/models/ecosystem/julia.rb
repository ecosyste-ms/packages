# frozen_string_literal: true

module Ecosystem
  class Julia < Base
    def registry_url(package, version = nil)
      "#{@registry_url}/ui/Packages/#{package.name}/#{package.metadata['slug']}/#{version}"
    end

    def check_status_url(package)
      "#{@registry_url}/ui/Packages/#{package.name}/#{package.metadata['slug']}"
    end

    def documentation_url(package, version = nil)
      "https://docs.juliahub.com/#{package.name}/#{package.metadata['slug']}/#{version}"
    end

    def install_command(package, version = nil)
      if version
        "Pkg.add(Pkg.PackageSpec(;name=\"#{package.name}\", version=\"#{version}\"))"
      else
        "Pkg.add(\"#{package.name}\")"
      end
    end

    def packages
      @packages ||= begin
        get_json("#{@registry_url}/app/packages/info")['packages']
      rescue
        {}
      end
    end

    def all_package_names
      packages.map{|p| p['name'] }
    end

    def recently_updated_package_names
      u = "https://github.com/JuliaRegistries/General/commits/master/Registry.toml.atom"
      titles = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      titles.map { |t| t.split(" ")[2] }.uniq
    rescue
      []
    end

    def fetch_package_metadata(name)
      packages.find{|pkg| pkg['name'] == name}
    end

    def map_package_metadata(package)
      return false unless package
      return false unless package['metadata']['docslink']
      slug = package['metadata']['docslink'].split('/')[2]
      json = get_json("#{@registry_url}/docs/#{package['name']}/#{slug}/pkg.json")
      {
        name: package['name'],
        description: package['metadata']['description'],
        homepage: json['homepage'],
        repository_url: repo_fallback(package['metadata']['repo'], json['homepage']),
        keywords_array: package['metadata']['tags'],
        versions: package['metadata']['versions'],
        licenses: package['license'],
        metadata: {
          uuid: package['uuid'],
          slug: slug
        }
      }
    end

    def versions_metadata(package)
      package[:versions].map do |v|
        {
          number: v,
        }
      end
    end

    def dependencies_metadata(name, version, package)
      json = get_json("#{@registry_url}/docs/#{package[:name]}/#{package[:metadata][:slug]}/#{version}/pkg.json")
      json['deps'].map do |dep|
        next if dep['direct'] == false
        next if dep['versions'].join(',') == '*' # skip std libraries
        {
          package_name: dep['name'],
          requirements: dep['versions'].join(','),
          kind: 'runtime',
          ecosystem: self.class.name.demodulize.downcase
        }
      end.compact
    end
  end
end
