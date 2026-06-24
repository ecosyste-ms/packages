# frozen_string_literal: true

module Ecosystem
  class Huggingface < Base
    API_URL = "https://huggingface.co/api/models".freeze

    def registry_url(package, version = nil)
      url = "#{@registry_url}/#{package.name}"
      url += "/tree/#{version}" if version.present?
      url
    end

    def download_url(package, version = nil)
      revision = version.presence || "main"
      "#{@registry_url}/#{package.name}/resolve/#{revision}/config.json"
    end

    def documentation_url(package, _version = nil)
      registry_url(package)
    end

    def install_command(package, version = nil)
      revision_part = version ? " --revision #{version}" : ""
      "huggingface-cli download #{package.name}#{revision_part}"
    end

    def check_status(package)
      model = fetch_package_metadata(package.name)
      return nil if model.present? && model.is_a?(Hash) && model["id"].present?

      "removed"
    end

    def all_package_names
      get_json("#{API_URL}?#{URI.encode_www_form(limit: 100)}").map { |model| model["id"] }.compact
    rescue
      []
    end

    def recently_updated_package_names
      get_json("#{API_URL}?#{URI.encode_www_form(limit: 100, sort: 'lastModified', direction: -1)}").map { |model| model["id"] }.compact
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      get_json("#{API_URL}/#{name}")
    rescue
      nil
    end

    def map_package_metadata(model)
      return false unless model.present?

      license = model.dig("cardData", "license").presence || license_from_tags(model["tags"])

      {
        name: model["id"] || model["modelId"],
        description: model.dig("cardData", "summary") || model["pipeline_tag"],
        homepage: registry_url(Package.new(name: model["id"] || model["modelId"])),
        repository_url: registry_url(Package.new(name: model["id"] || model["modelId"])),
        keywords_array: Array.wrap(model["tags"]),
        licenses: license || "Unknown",
        downloads: model["downloads"],
        downloads_period: "total",
        versions: [model["sha"]].compact,
        metadata: {
          "author" => model["author"],
          "sha" => model["sha"],
          "pipeline_tag" => model["pipeline_tag"],
          "library_name" => model["library_name"],
          "last_modified" => model["lastModified"],
          "siblings" => Array.wrap(model["siblings"]).map { |sibling| sibling["rfilename"] }.compact
        }
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkg_metadata[:versions]
        .reject { |version| existing_version_numbers.include?(version) }
        .map do |version|
          {
            number: version,
            published_at: pkg_metadata.dig(:metadata, "last_modified"),
            licenses: pkg_metadata[:licenses],
            metadata: pkg_metadata[:metadata]
          }
        end
    end

    def purl_params(package, version = nil)
      namespace, name = package.name.split('/', 2)
      {
        type: purl_type,
        namespace: namespace,
        name: (name || namespace).encode('iso-8859-1'),
        version: version.try(:number).try(:encode, 'iso-8859-1')
      }
    end

    def self.purl_type
      "huggingface"
    end

    private

    def license_from_tags(tags)
      Array.wrap(tags).find { |tag| tag.start_with?("license:") }&.delete_prefix("license:")
    end
  end
end
