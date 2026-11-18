# frozen_string_literal: true

module Ecosystem
  class Ollama < Base
    OCI_REGISTRY = "registry.ollama.ai"
    NAMESPACE = "library"
    NAME_FORMAT = /\A[a-z0-9][a-z0-9._-]*\z/i
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
      library_names("#{@registry_url}/#{NAMESPACE}")
    rescue => e
      Rails.logger.warn("Error listing Ollama models: #{e.message}")
      []
    end

    def recently_updated_package_names
      library_names("#{@registry_url}/#{NAMESPACE}?sort=newest")
    rescue => e
      Rails.logger.warn("Error listing recently updated Ollama models: #{e.message}")
      []
    end

    def fetch_package_metadata_uncached(name)
      return false unless name.to_s.match?(NAME_FORMAT)

      response = request("#{@registry_url}/#{NAMESPACE}/#{name}/tags")
      return false if [400, 404, 410].include?(response.status)
      return nil unless response.success?

      doc = Nokogiri::HTML(response.body)
      tags = parse_tags(doc, name)
      # A page with no tags for this model is a markup change or another model's page, not a removal
      return nil if tags.empty?

      config_tag = tags.find { |tag| tag["name"] == "latest" } || tags.first
      downloads_label = doc.css("span").find { |span| span.elements.empty? && span.text.end_with?("Downloads") }

      {
        "name" => name,
        "description" => doc.at_css("meta[name=description]")&.[]("content"),
        "updated_at" => doc.at_css("[title$='UTC']")&.[]("title"),
        # Parameter sizes share the capability pills, so drop them
        "keywords" => doc.css("span.inline-flex.rounded-md").map { |span| span.text.strip }.reject { |pill| pill.match?(/\Ae?[\d.]+[kmb]\z/i) }.uniq,
        "pulls" => parse_pulls(downloads_label&.previous_element&.text),
        "tags" => tags,
        "config" => fetch_config(name, config_tag["name"])
      }
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
      return if versions_metadata.empty?

      listed = versions_metadata.index_by { |version| version[:number] }
      now = Time.current

      package.versions.find_each do |version|
        incoming = listed[version.number]
        if incoming.nil?
          version.update_columns(status: "removed", updated_at: now) unless version.status == "removed"
          next
        end

        updates = {}
        updates[:status] = nil if version.status == "removed"

        expected = incoming[:short_digest].presence || incoming.dig(:metadata, :digest).to_s.delete_prefix("sha256:")
        current = version.metadata.to_h["digest"].to_s.delete_prefix("sha256:")
        if expected.present? && !current.start_with?(expected)
          fresh = incoming[:metadata] || version_metadata(package.name, version.number)&.fetch(:metadata)
          updates[:metadata] = fresh if fresh
        end

        version.update_columns(updates.merge(updated_at: now)) if updates.any?
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
      return nil if response.status == 404
      raise "Ollama registry returned #{response.status} for #{name}:#{tag}" unless response.success?

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

    def library_names(url)
      response = request(url)
      raise "Ollama returned #{response.status} for #{url}" unless response.success?

      Nokogiri::HTML(response.body).css("a[href^='/#{NAMESPACE}/']")
        .map { |link| link["href"].delete_prefix("/#{NAMESPACE}/") }
        .select { |name| name.match?(NAME_FORMAT) }
        .uniq
    end

    def parse_tags(doc, name)
      doc.css("div.group").filter_map do |row|
        tag = row.at_css("a[href^='/#{NAMESPACE}/#{name}:']")&.[]("href")&.split(":", 2)&.last
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
