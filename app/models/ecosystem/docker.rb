# frozen_string_literal: true

module Ecosystem
  class Docker < Base

    def registry_url(package, version = nil)
      if version && version['metadata']['images'].present?
        "https://hub.docker.com/layers/#{package.name}/#{version['number']}/images/#{version['metadata']['images'].first['digest']}"
      else
        "https://hub.docker.com/r/#{package.name}"
      end      
    end

    def install_command(package, version = nil)
      "docker pull #{package.name}" + (version ? ":#{version}" : "")
    end

    def check_status_url(package)
      "https://hub.docker.com/v2/repositories/#{package.name}"
    end

    def fetch_package_metadata(name)
      get_json("https://hub.docker.com/v2/repositories/#{name}/")
    end

    def recently_updated_package_names
      json = get_json("https://hub.docker.com/api/content/v1/products/search/?sort=updated_at&order=desc&page_size=100", headers: {"Search-Version" => "v3"})
      json['summaries'].map{|s| s['slug'] }
    rescue
      []
    end

    def org_package_names(name)
      page = 1
      images = []
      while page < 100
        r = get("https://hub.docker.com/v2/repositories/#{name}/?page=#{page}&page_size=100")
        break if r['results'].nil? || r['results'] == []

        images += r['results']
        break if r['next'].nil?
        page += 1
      end
      images.map{|i| "#{i["namespace"]}/#{i["name"]}" }
    end

    def all_package_names
      official_packages = org_package_names('library')
      community_packages = get_json("https://repos.ecosyste.ms/api/v1/package_names/docker")
      (official_packages + community_packages).uniq
    end

    def map_package_metadata(package)
      return nil unless package["name"]
      package_name = "#{package["namespace"]}/#{package["name"]}"
      {
        name: package_name,
        description: package["description"],
        repository_url: load_repository_url(package_name),
        namespace: package["namespace"],
        downloads: package["pull_count"],
        downloads_period: "total",
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      page = 1
      tags = []
      while page < 10
        r = get("https://hub.docker.com/v2/repositories/#{pkg_metadata[:name]}/tags?page=#{page}&page_size=100")
        break if r['results'].nil? || r['results'] == []

        tags += r['results']
        break if r['next'].nil?
        page += 1
      end
      tags.map do |version|
        {
          number: version["name"],
          published_at: version["last_updated"],
          metadata: {
            images: version["images"]
          }
        }
      end.compact
    end

    def load_repository_url(name)
      return 'https://github.com/docker-library/official-images' if name.start_with?('library/')
      json = get("https://hub.docker.com/api/build/v1/source/?image=#{name}")
      return unless json['objects']
      o = json['objects'].first
      return unless o
      return unless o['provider'] == 'Github'
      "https://github.com/#{o['owner']}/#{o['repository']}"
    end
  end
end
