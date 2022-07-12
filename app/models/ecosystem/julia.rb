# frozen_string_literal: true

module Ecosystem
  class Julia < Base
    def registry_url(package, version = nil)
      "https://juliahub.com/ui/Packages/#{package.name}/#{package.metadata['slug']}/#{version}"
    end

    def check_status_url(package)
      "https://juliahub.com/ui/Packages/#{package.name}/#{package.metadata['slug']}"
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
        get_json('https://juliahub.com/app/packages/info')['packages']
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
      {
        name: package['name'],
        description: package['metadata']['description'],
        repository_url: package['metadata']['repo'],
        keywords_array: package['metadata']['tags'],
        versions: package['metadata']['versions'],
        licenses: package['license'],
        metadata: {
          uuid: package['uuid'],
          slug: package['metadata']['docslink'].split('/')[2]
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
  end
end
