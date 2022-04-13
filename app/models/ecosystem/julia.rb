# frozen_string_literal: true

module Ecosystem
  class Julia < Base
    def package_url(package, version = nil)
      # package hash = 'nfu7T'
      "https://juliahub.com/ui/Packages/#{package.name}/#{}/#{version}"
    end

    def packages
      @packages ||= get_json('https://juliahub.com/app/packages/info')['packages']
    end

    def all_package_names
      packages.map{|p| p['name'] }
    end

    def recently_updated_package_names
      u = "https://github.com/JuliaRegistries/General/commits/master/Registry.toml.atom"
      titles = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      titles.map { |t| t.split(" ")[2] }.uniq
    end

    def fetch_package_metadata(name)
      versions = `ls METADATA.jl/#{name}/versions`.split("\n").sort
      repository_url = `cat METADATA.jl/#{name}/url`
      {
        name: name,
        versions: versions,
        repository_url: repository_url,
      }
    end

    def map_package_metadata(raw_package)
      {
        name: raw_package[:name],
        repository_url: repo_fallback(raw_package[:repository_url], ""),
      }
    end

    def versions_metadata(raw_package, _name)
      raw_package["versions"].map do |v|
        {
          number: v,
        }
      end
    end
  end
end
