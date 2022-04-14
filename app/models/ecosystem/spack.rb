# frozen_string_literal: true

module Ecosystem
  class Spack < Base
    def registry_url(package, version = nil)
      "#{@registry_url}/packages/package.html?name=#{package.name}"
    end

    def install_command(package, version = nil)
      "spack install #{package.name}" + (version ? "@#{version}" : "")
    end

    def all_package_names
      get_json("#{@registry_url}/packages/data/packages.json")
    rescue StandardError
      {}
    end

    def recently_updated_package_names
      all_package_names
    end

    def fetch_package_metadata(name)
      get_json("#{@registry_url}/packages/data/packages/#{name}.json")
    rescue StandardError
      {}
    end

    def map_package_metadata(package)
      {
        name: package["name"],
        description: package["description"],
        homepage: package["homepage"],
        licenses: [],
        repository_url: package["homepage"],
        versions: package["versions"],
        dependencies: package['dependencies']
      }
    end

    def versions_metadata(package)
      package[:versions].map do |v|
        {
          number: v["name"],
        }
      end
    rescue StandardError
      []
    end

    def dependencies_metadata(name, version, package)
      return [] unless package[:dependencies]

      package[:dependencies].map do |dep|
        {
          package_name: dep["name"],
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