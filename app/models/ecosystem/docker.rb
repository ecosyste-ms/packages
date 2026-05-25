# frozen_string_literal: true

module Ecosystem
  class Docker < Base

    ECR_PUBLIC_API_URL = "https://api.us-east-1.gallery.ecr.aws"

    def registry_url(package, version = nil)
      if ecr_public_registry?
        "https://gallery.ecr.aws/#{package.name}"
      elsif version && version['metadata']['images'].present?
        "https://hub.docker.com/layers/#{package.name}/#{version['number']}/images/#{version['metadata']['images'].first['digest']}"
      else
        "https://hub.docker.com/r/#{package.name}"
      end      
    end

    def install_command(package, version = nil)
      image_name = ecr_public_registry? ? "public.ecr.aws/#{package.name}" : package.name
      "docker pull #{image_name}" + (version ? ":#{version}" : "")
    end

    def check_status(package)
      pkg = fetch_package_metadata(package.name)
      return nil if pkg.present? && pkg.is_a?(Hash) && (pkg["name"].present? || pkg["catalogData"].present?)

      # Fall back to a direct request if not cached
      url = check_status_url(package)
      response = Faraday.head(url)
      return "removed" if [400, 404, 410].include?(response.status)
    end

    def check_status_url(package)
      if ecr_public_registry?
        "https://gallery.ecr.aws/#{package.name}"
      else
        "https://hub.docker.com/v2/repositories/#{package.name}"
      end
    end

    def fetch_package_metadata_uncached(name)
      if ecr_public_registry?
        registry_alias_name, repository_name = ecr_public_package_parts(name)
        return {} if registry_alias_name.blank? || repository_name.blank?

        metadata = ecr_public_post("getRepositoryCatalogData", {
          registryAliasName: registry_alias_name,
          repositoryName: repository_name
        }) || {}
        metadata.merge("registryAliasName" => registry_alias_name, "repositoryName" => repository_name)
      else
        name = "library/#{name}" if name.split('/').length == 1
        get_json("https://hub.docker.com/v2/repositories/#{name}/")
      end
    rescue
      {}
    end

    def recently_updated_package_names
      json = get_json("https://hub.docker.com/api/content/v1/products/search/?sort=updated_at&order=desc&page_size=100", headers: {"Search-Version" => "v3"})
      json['summaries'].map{|s| s['slug'] }
    rescue
      []
    end

    def namespace_package_names(name)
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
      if ecr_public_registry?
        ecr_public_search_results.map do |repository|
          [repository["primaryRegistryAliasName"], repository["repositoryName"]].compact.join("/")
        end.uniq
      else
        official_packages = namespace_package_names('library')
        community_packages = get_json("https://repos.ecosyste.ms/api/v1/package_names/docker")
        (official_packages + community_packages).uniq
      end
    rescue
      []
    end

    def map_package_metadata(package)
      if ecr_public_registry?
        map_ecr_public_package_metadata(package)
      else
        return nil unless package && package["name"]
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
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      return ecr_public_versions_metadata(pkg_metadata) if ecr_public_registry?

      page = 1
      tags = []
      while page < 10
        r = get("https://hub.docker.com/v2/repositories/#{pkg_metadata[:name]}/tags?page=#{page}&page_size=100")
        break if r.blank? || r['results'].nil? || r['results'] == []

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
    rescue 
      []
    end

    def load_repository_url(name)
      return 'https://github.com/docker-library/official-images' if name.start_with?('library/')
      json = get("https://hub.docker.com/api/build/v1/source/?image=#{name}")
      return unless json && json['objects']
      o = json['objects'].first
      return unless o
      return unless o['provider'] == 'Github'
      "https://github.com/#{o['owner']}/#{o['repository']}"
    end

    private

    def ecr_public_registry?
      registry_url.to_s.include?("gallery.ecr.aws")
    end

    def ecr_public_post(action, body)
      response = Faraday.post("#{ECR_PUBLIC_API_URL}/#{action}") do |request|
        request.headers["Content-Type"] = "application/json"
        request.headers["Accept"] = "application/json"
        request.headers["User-Agent"] = "packages.ecosyste.ms"
        request.body = body.to_json
      end
      return nil unless response.success?

      Oj.load(response.body)
    rescue
      nil
    end

    def ecr_public_package_parts(name)
      name.to_s.split("/", 2)
    end

    def ecr_public_search_results
      next_token = nil
      repositories = []

      loop do
        body = { maxResults: 100 }
        body[:nextToken] = next_token if next_token.present?
        response = ecr_public_post("searchRepositoryCatalogData", body)
        break if response.blank?

        repositories.concat(response["repositoryCatalogSearchResultList"] || [])
        next_token = response["nextToken"]
        break if next_token.blank?
      end

      repositories
    end

    def map_ecr_public_package_metadata(package)
      catalog_data = package["catalogData"] || package
      registry_alias_name = package["registryAliasName"] || package["primaryRegistryAliasName"]
      repository_name = package["repositoryName"]
      return nil if registry_alias_name.blank? || repository_name.blank?

      {
        name: "#{registry_alias_name}/#{repository_name}",
        description: catalog_data["description"],
        homepage: catalog_data["sourceCodeRepository"],
        repository_url: repo_fallback(catalog_data["sourceCodeRepository"], catalog_data["aboutText"]),
        namespace: registry_alias_name,
        downloads: catalog_data["downloadCount"] || package["downloadCount"],
        downloads_period: "total",
        metadata: catalog_data.except("description", "downloadCount")
      }
    end

    def ecr_public_versions_metadata(pkg_metadata)
      registry_alias_name, repository_name = ecr_public_package_parts(pkg_metadata[:name])
      response = ecr_public_post("describeImageTags", {
        registryAliasName: registry_alias_name,
        repositoryName: repository_name,
        maxResults: 100
      })

      Array(response && response["imageTagDetails"]).map do |tag|
        {
          number: tag["imageTag"],
          published_at: tag["createdAt"] || tag.dig("imageDetail", "imagePushedAt"),
          metadata: tag.except("imageTag")
        }
      end
    rescue
      []
    end
  end
end
