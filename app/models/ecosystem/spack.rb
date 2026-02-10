# frozen_string_literal: true

module Ecosystem
  class Spack < Base
    def registry_url(package, version = nil)
      "#{@registry_url}/package.html?name=#{package.name}"
    end

    def install_command(package, version = nil)
      "spack install #{package.name}" + (version ? "@#{version}" : "")
    end

    def download_url(_package, version)
      return nil unless version.present?
      url = version.metadata['download_url']
      url.is_a?(Array) ? url.first : url
    end

    def package_data
      @package_data || get_json("#{@registry_url}/data/repology.json")
    end

    def check_status(package)
      return 'removed' if package_data["packages"][package.name].nil?
    end

    def all_package_names
      package_data["packages"].keys.sort
    rescue StandardError
      []
    end

    def recently_updated_package_names
      u = "https://github.com/spack/spack/commits/develop.atom"
      titles = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      titles.map { |t| t.split(/[\s,:]/)[0] }.uniq
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      json = get_json("#{@registry_url}/data/packages/#{name}.json")
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

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkg_metadata[:versions].map do |v|
        download_url = v['downloads'].is_a?(Array) ? v['downloads'].first : v['downloads']
        {
          number: v["version"],
          integrity: "sha256-" + v['sha256'],
          metadata: {
            download_url: download_url
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

    def maintainers_metadata(name)
      json = get_json("#{@registry_url}/data/packages/#{name}.json")
      json["maintainers"].map do |m|
        {
          uuid: m,
          login: m,
          url: "https://github.com/#{m}",
        }
      end
    end
  end
end