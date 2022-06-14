# frozen_string_literal: true

module Ecosystem
  class Spack < Base
    def registry_url(package, version = nil)
      "#{@registry_url}/packages/package.html?name=#{package.name}"
    end

    def install_command(package, version = nil)
      "spack install #{package.name}" + (version ? "@#{version}" : "")
    end

    def download_url(_package, version)
      version.metadata['download_url']
    end

    def package_data
      @package_data || get_json("#{@registry_url}/packages/data/repology.json")
    end

    def all_package_names
      package_data["packages"].keys.sort
    rescue StandardError
      {}
    end

    def recently_updated_package_names
      u = "https://github.com/spack/spack/commits/develop.atom"
      titles = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      titles.map { |t| t.split(/[\s,:]/)[0] }.uniq
    rescue
      []
    end

    def fetch_package_metadata(name)
      json = get_json("#{@registry_url}/packages/data/packages/#{name}.json")
      data = package_data["packages"][name]
      data["name"] = name
      json 
      json["versions"].each do |v|
        data['version'].find{|vv| vv["version"] == v["name"]}['sha256'] = v['sha256']
      end
      data
    rescue StandardError
      {}
    end

    def map_package_metadata(package)
      return false unless package["name"].present?
      {
        name: package["name"],
        description: package["summary"],
        homepage: package.fetch("homepages", []).first,
        licenses: [],
        repository_url: package.fetch("homepages", []).first,
        versions: package["version"],
        dependencies: package['dependencies']
      }
    end

    def versions_metadata(package)
      package[:versions].map do |v|
        {
          number: v["version"],
          integrity: "sha256-" + v['sha256'],
          metadata: {
            download_url: v['downloads'].first
          }
        }
      end
    rescue StandardError
      []
    end

    def dependencies_metadata(name, version, package)
      return [] unless package[:dependencies]

      package[:dependencies].map do |dep|
        {
          package_name: dep,
          requirements: '*',
          kind: 'runtime',
          ecosystem: self.class.name.demodulize.downcase
        }
      end
    rescue StandardError
      []
    end
  end
end