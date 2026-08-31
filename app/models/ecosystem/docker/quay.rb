# frozen_string_literal: true

module Ecosystem
  class Docker
    class Quay < Docker
      def registry_url(package, _version = nil)
        "https://quay.io/repository/#{package.name}"
      end

      def check_status_url(package)
        "https://quay.io/api/v1/repository/#{package.name}?includeTags=false"
      end

      def fetch_package_metadata_uncached(name)
        json = get_json("https://quay.io/api/v1/repository/#{name}?includeTags=false&includeStats=true")
        return nil unless json && json['name']
        json
      rescue
        nil
      end

      def map_package_metadata(package)
        return nil unless package && package['name']
        full_name = "#{package['namespace']}/#{package['name']}"
        {
          name: full_name,
          namespace: package['namespace'],
          description: package['description'],
          repository_url: find_repository_url(URI.extract(package['description'].to_s, %w[http https]).map { |u| u.chomp(')').chomp('.') }),
          downloads: Array(package['stats']).sum { |d| d['count'].to_i },
          downloads_period: 'last-90-days',
          status: package['state'] == 'NORMAL' ? nil : package['state']&.downcase,
        }
      end

      def versions_metadata(pkg_metadata, existing_version_numbers = [])
        page = 1
        tags = []
        while page <= 20
          json = get_json("https://quay.io/api/v1/repository/#{pkg_metadata[:name]}/tag/?limit=100&onlyActiveTags=true&page=#{page}")
          break unless json && json['tags'].present?
          tags.concat(json['tags'])
          break unless json['has_additional']
          page += 1
        end
        tags.map do |t|
          {
            number: t['name'],
            published_at: t['last_modified'],
            metadata: {
              digest: t['manifest_digest'],
              size: t['size'],
            },
          }
        end
      rescue
        []
      end

      def all_package_names
        list_repositories
      end

      def namespace_package_names(namespace)
        list_repositories(namespace: namespace)
      end

      def list_repositories(namespace: nil)
        names = []
        cursor = nil
        loop do
          url = "https://quay.io/api/v1/repository?public=true"
          url += "&namespace=#{CGI.escape(namespace)}" if namespace
          url += "&next_page=#{CGI.escape(cursor)}" if cursor
          json = get_json(url)
          break unless json && json['repositories'].present?
          names.concat(json['repositories'].map { |r| "#{r['namespace']}/#{r['name']}" })
          cursor = json['next_page']
          break unless cursor
        end
        names
      rescue
        []
      end
    end
  end
end
