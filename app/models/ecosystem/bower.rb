# frozen_string_literal: true
module Ecosystem
  class Bower < Base
    def install_command(package, version = nil)
      "bower install #{package.name}" + (version ? "##{version}" : "")
    end

    def all_package_names
      packages.keys
    end

    def recently_updated_package_names
      []
    end

    def packages
      @packages ||= begin
        packages = {}
        data = get("https://registry.bower.io/packages")

        data.each do |hash|
          packages[hash['name'].downcase] = hash.slice('name', 'url')
        end

        packages
      rescue
        {}
      end
    end

    def versions_metadata(name)
      []
    end

    def fetch_package_metadata(name)
      packages[name.downcase]
    end

    def map_package_metadata(package)
      bower_json = load_bower_json(package) || package
      {
        name: package["name"],
        repository_url: package["url"],
        licenses: bower_json['license'],
        keywords_array: bower_json['keywords'],
        homepage: bower_json["homepage"],
        description: description(bower_json["description"])
      }
    end

    def description(string)
      return nil if string.nil?
      return '' unless string.force_encoding('UTF-8').valid_encoding?
      string
    end

    def load_bower_json(package)
      return package unless package['url']
      github_name_with_owner = GithubUrlParser.parse(package['url'])
      return package unless github_name_with_owner
      get_json("https://raw.githubusercontent.com/#{github_name_with_owner}/master/bower.json") rescue {}
    end
  end
end
