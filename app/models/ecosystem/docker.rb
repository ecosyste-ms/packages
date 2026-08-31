# frozen_string_literal: true

module Ecosystem
  class Docker < Base
    def self.for_registry(registry)
      case URI(registry.url).host
      when 'hub.docker.com' then Docker::Hub
      when 'quay.io' then Docker::Quay
      else self
      end
    end

    def self.purl_type
      'docker'
    end

    def install_command(package, version = nil)
      "docker pull #{image_ref(package.name)}" + (version ? ":#{version}" : "")
    end

    def check_status(package)
      pkg = fetch_package_metadata(package.name)
      return nil if pkg.present? && pkg.is_a?(Hash) && pkg["name"].present?

      url = check_status_url(package)
      response = Faraday.head(url)
      return "removed" if [400, 404, 410].include?(response.status)
    end

    def check_status_url(package)
      "#{@registry_url}/v2/#{package.name}/tags/list"
    end

    def fetch_package_metadata_uncached(name)
      tags = v2_tags(name)
      return nil unless tags
      { 'name' => name, 'namespace' => name.split('/')[0..-2].join('/').presence, 'tags' => tags }
    rescue
      nil
    end

    def map_package_metadata(package)
      return nil unless package && package['name']
      {
        name: package['name'],
        namespace: package['namespace'],
        tags: package['tags'],
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      Array(pkg_metadata[:tags]).map { |t| { number: t } }
    end

    def all_package_names
      prefix = "#{registry_host}/"
      get_json_array("https://repos.ecosyste.ms/api/v1/package_names/docker")
        .select { |n| n.start_with?(prefix) }
        .map { |n| n.delete_prefix(prefix) }
    rescue
      []
    end

    def recently_updated_package_names
      []
    end

    def registry_host
      @registry_host ||= URI(@registry_url).host
    end

    def image_ref(name)
      @registry.default ? name : "#{registry_host}/#{name}"
    end

    def v2_tags(name)
      tags = []
      path = "/v2/#{name}/tags/list?n=1000"
      50.times do
        resp = v2_get(path)
        return nil if resp.nil?
        json = JSON.parse(resp.body)
        tags.concat(json['tags'] || [])
        link = resp.headers['link']
        break unless link && link =~ /<([^>]+)>;\s*rel="next"/
        path = $1
      end
      tags
    end

    def v2_get(path)
      resp = Faraday.get("#{@registry_url}#{path}")
      if resp.status == 401 && (challenge = resp.headers['www-authenticate'])
        params = challenge.sub(/^Bearer /i, '').scan(/(\w+)="([^"]+)"/).to_h
        realm = params.delete('realm')
        return nil unless realm
        token = get_json("#{realm}?#{params.to_query}")&.dig('token')
        return nil unless token
        resp = Faraday.get("#{@registry_url}#{path}", nil, { 'Authorization' => "Bearer #{token}" })
      end
      resp.status == 200 ? resp : nil
    end
  end
end
