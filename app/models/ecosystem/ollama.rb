# frozen_string_literal: true

module Ecosystem
  class Ollama < Base
    OCI_REGISTRY = "registry.ollama.ai"
    NAMESPACE = "library"
    LIBRARY_CACHE_KEY = "ollama/library/v1"
    PULL_MULTIPLIERS = { "K" => 1_000, "M" => 1_000_000, "B" => 1_000_000_000 }.freeze

    def self.purl_type
      "oci"
    end

    def has_dependent_repos?
      false
    end

    def include_repository_url_in_purl?
      false
    end

    # The oci repository_url qualifier names the registry host and repository path, not the website.
    def purl_repository_url?(url, name)
      url.to_s.casecmp?("#{OCI_REGISTRY}/#{NAMESPACE}/#{name}")
    end

    def purl_params(package, version = nil)
      qualifiers = { "repository_url" => "#{OCI_REGISTRY}/#{NAMESPACE}/#{package.name}" }
      qualifiers["tag"] = version.number if version

      {
        type: purl_type,
        namespace: nil,
        name: package.name,
        version: version.try(:metadata).to_h["digest"].presence,
        qualifiers: qualifiers
      }
    end

    def registry_url(package, version = nil)
      url = "#{@registry_url}/#{NAMESPACE}/#{package.name}"
      version.present? ? "#{url}:#{version}" : url
    end

    def documentation_url(package, version = nil)
      registry_url(package, version)
    end

    def install_command(package, version = nil)
      command = "ollama pull #{package.name}"
      version.present? ? "#{command}:#{version}" : command
    end

    def check_status(package)
      metadata = fetch_package_metadata(package.name)
      return "removed" if metadata == false
      return false if metadata.nil?

      nil
    end

    def all_package_names
      library.keys
    rescue => e
      Rails.logger.warn("Error listing Ollama models: #{e.message}")
      []
    end

    def recently_updated_package_names
      parse_library(fetch_html("#{@registry_url}/#{NAMESPACE}?sort=newest")).keys
    rescue => e
      Rails.logger.warn("Error listing recently updated Ollama models: #{e.message}")
      []
    end

    def fetch_package_metadata_uncached(name)
      response = request("#{@registry_url}/#{NAMESPACE}/#{name}/tags")
      return false if [400, 404, 410].include?(response.status)
      return nil unless response.success?

      doc = Nokogiri::HTML(response.body)
      tags = parse_tags(doc)
      config_tag = tags.find { |tag| tag["name"] == "latest" } || tags.first

      {
        "name" => name,
        "description" => doc.at_css("meta[name=description]")&.[]("content"),
        "updated_at" => doc.at_css("[title$='UTC']")&.[]("title"),
        "tags" => tags,
        "config" => config_tag ? fetch_config(name, config_tag["name"]) : nil
      }.merge(library[name].to_h.slice("keywords", "pulls"))
    rescue => e
      Rails.logger.warn("Error fetching Ollama model #{name}: #{e.message}")
      nil
    end

    def map_package_metadata(model)
      return false unless model.is_a?(Hash) && model["name"].present?

      config = model["config"].to_h
      tags = Array(model["tags"])

      {
        name: model["name"],
        description: model["description"],
        keywords_array: Array(model["keywords"]),
        downloads: model["pulls"],
        downloads_period: "total",
        versions: tags,
        metadata: {
          "dist-tags": tags.any? { |tag| tag["name"] == "latest" } ? { "latest" => "latest" } : nil,
          updated_at: model["updated_at"],
          model_format: config["model_format"],
          model_family: config["model_family"],
          parameter_size: config["model_type"],
          quantization: config["file_type"]
        }.compact
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      Array(pkg_metadata[:versions]).filter_map do |tag|
        # Existing tags are passed through unfetched so update_existing_versions can spot moved ones
        next { number: tag["name"], short_digest: tag["digest"] } if existing_version_numbers.include?(tag["name"])

        version_metadata(pkg_metadata[:name], tag["name"])
      end
    end

    def update_existing_versions(package, versions_metadata)
      short_digests = versions_metadata.to_h { |version| [version[:number], version[:short_digest]] }.compact
      return if short_digests.empty?

      package.versions.where(number: short_digests.keys).find_each do |version|
        next if version.metadata.to_h["digest"].to_s.delete_prefix("sha256:").start_with?(short_digests[version.number])

        fresh = version_metadata(package.name, version.number)
        version.update_columns(metadata: fresh[:metadata], updated_at: Time.current) if fresh
      end
    end

    def version_metadata(name, tag)
      fetched = fetch_manifest(name, tag)
      return nil if fetched.nil?

      layers = Array(fetched["manifest"]["layers"])

      {
        number: tag,
        metadata: {
          digest: fetched["digest"],
          size: layers.sum { |layer| layer["size"].to_i },
          media_types: layers.filter_map { |layer| layer["mediaType"] }.uniq
        }
      }
    end

    def fetch_manifest(name, tag)
      response = request(blob_url(name, "manifests", tag), headers: { "Accept" => "application/vnd.docker.distribution.manifest.v2+json" })
      return nil unless response.success?

      digest = response.headers["ollama-content-digest"].presence || Digest::SHA256.hexdigest(response.body)
      { "digest" => "sha256:#{digest}", "manifest" => Oj.load(response.body) }
    end

    def fetch_config(name, tag)
      digest = fetch_manifest(name, tag)&.dig("manifest", "config", "digest")
      return nil if digest.blank?

      response = request(blob_url(name, "blobs", digest))
      response.success? ? Oj.load(response.body) : nil
    end

    def blob_url(name, kind, reference)
      "https://#{OCI_REGISTRY}/v2/#{NAMESPACE}/#{name}/#{kind}/#{reference}"
    end

    def library
      Rails.cache.fetch(LIBRARY_CACHE_KEY, expires_in: 1.hour) do
        parse_library(fetch_html("#{@registry_url}/#{NAMESPACE}"))
      end
    end

    def fetch_html(url)
      response = request(url)
      raise "Ollama returned #{response.status} for #{url}" unless response.success?

      Nokogiri::HTML(response.body)
    end

    def parse_library(doc)
      doc.css("a[href^='/#{NAMESPACE}/']").each_with_object({}) do |link, models|
        name = link["href"].delete_prefix("/#{NAMESPACE}/")
        next if name.blank? || name.match?(%r{[/:]})

        pulls_label = link.css("span").find { |span| span.elements.empty? && span.text.end_with?("Pulls") }
        models[name] = {
          # Parameter sizes share the capability pills, so drop them
          "keywords" => link.css("span.inline-flex").map { |span| span.text.strip }.reject { |pill| pill.match?(/\Ae?[\d.]+[kmb]\z/i) },
          "pulls" => parse_pulls(pulls_label&.previous_element&.text)
        }
      end
    end

    def parse_tags(doc)
      doc.css("div.group").filter_map do |row|
        tag = row.at_css("a[href*=':']")&.[]("href")&.split(":", 2)&.last
        next if tag.blank?

        { "name" => tag, "digest" => row.at_css(".font-mono")&.text&.strip }
      end
    end

    def parse_pulls(text)
      match = text.to_s.strip.match(/\A([\d.]+)([KMB])?\z/)
      return nil unless match

      (match[1].to_f * PULL_MULTIPLIERS.fetch(match[2], 1)).round
    end
  end
end
