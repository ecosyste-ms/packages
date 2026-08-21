# frozen_string_literal: true

module Ecosystem
  class Huggingface < Base
    API_URL = "https://huggingface.co/api/models"
    PAGE_SIZE = 1_000
    SYNC_MISSING_CURSOR_KEY = "sync_missing_packages_cursor"

    def has_dependent_repos?
      false
    end

    def sync_missing_packages_incrementally?
      true
    end

    def sync_missing_packages_async
      response = request(sync_missing_packages_cursor)
      raise "Hugging Face models API returned #{response.status}" unless response.success?

      names = Oj.load(response.body).filter_map { |model| model["id"].presence || model["modelId"].presence }.uniq
      existing_names = @registry.packages.where(name: names).pluck(:name).to_set
      jobs = names.reject { |name| existing_names.include?(name) }.map { |name| [@registry.id, name] }
      jobs.each_slice(1_000) { |batch| SyncPackageWorker.perform_bulk(batch) }

      save_sync_missing_packages_cursor(next_page_url(response.headers["link"]))
      jobs.length
    rescue => e
      Rails.logger.error("Error syncing missing Hugging Face models for registry #{@registry.id}: #{e.message}")
      0
    end

    def purl_params(package, version = nil)
      namespace, name = package.name.split("/", 2)
      {
        type: purl_type,
        namespace: name.present? ? namespace : nil,
        name: (name || namespace).encode("iso-8859-1"),
        version: version.try(:number).try(:encode, "iso-8859-1")
      }
    end

    def registry_url(package, version = nil)
      url = "#{@registry_url}/#{package.name}"
      version.present? ? "#{url}/tree/#{version}" : url
    end

    def download_url(_package, _version = nil)
      nil
    end

    def documentation_url(package, version = nil)
      registry_url(package, version)
    end

    def install_command(package, version = nil)
      command = "hf download #{package.name}"
      version.present? ? "#{command} --revision #{version}" : command
    end

    def check_status(package)
      return "removed" if fetch_package_metadata(package.name) == false

      nil
    end

    def all_package_names
      names = []
      url = catalogue_url

      while url.present?
        response = request(url)
        raise "Hugging Face models API returned #{response.status}" unless response.success?

        names.concat(Oj.load(response.body).filter_map { |model| model["id"].presence || model["modelId"].presence })
        url = next_page_url(response.headers["link"])
      end

      names.uniq
    rescue => e
      Rails.logger.warn("Error listing Hugging Face models: #{e.message}")
      []
    end

    def recently_updated_package_names
      get_json_array("#{API_URL}?limit=100&sort=lastModified&direction=-1")
        .filter_map { |model| model["id"].presence || model["modelId"].presence }
    rescue => e
      Rails.logger.warn("Error listing recently updated Hugging Face models: #{e.message}")
      []
    end

    def fetch_package_metadata_uncached(name)
      response = request("#{API_URL}/#{encoded_model_name(name)}")
      return false if [400, 404, 410].include?(response.status)
      return nil unless response.success?

      Oj.load(response.body)
    rescue => e
      Rails.logger.warn("Error fetching Hugging Face model #{name}: #{e.message}")
      nil
    end

    def map_package_metadata(model)
      return false unless model.is_a?(Hash)

      name = model["id"].presence || model["modelId"].presence
      return false if name.blank?

      namespace = name.split("/", 2).first if name.include?("/")

      {
        name: name,
        namespace: namespace,
        homepage: "#{@registry_url}/#{name}",
        licenses: license_for(model),
        keywords_array: Array(model["tags"]).reject(&:blank?),
        downloads: model["downloads"],
        downloads_period: "last-month",
        versions: [model],
        metadata: {
          author: model["author"],
          created_at: model["createdAt"],
          last_modified: model["lastModified"],
          likes: model["likes"],
          pipeline_tag: model["pipeline_tag"],
          library_name: model["library_name"],
          gated: model["gated"],
          private: model["private"],
          disabled: model["disabled"]
        }.compact
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      Array(pkg_metadata[:versions]).filter_map do |model|
        revision = model["sha"].presence
        next if revision.blank? || existing_version_numbers.include?(revision)

        {
          number: revision,
          published_at: model["lastModified"],
          metadata: {
            revision: revision,
            created_at: model["createdAt"],
            last_modified: model["lastModified"]
          }.compact
        }
      end.uniq { |version| version[:number] }
    end

    def next_page_url(link_header)
      link_header.to_s.split(",").each do |link|
        next unless link.match?(/rel=[\"']?next[\"']?/)

        url = link.match(/<([^>]+)>/)&.captures&.first
        return URI.join(API_URL, url).to_s if url.present?
      end

      nil
    end

    def sync_missing_packages_cursor
      @registry.metadata.to_h[SYNC_MISSING_CURSOR_KEY].presence || catalogue_url
    end

    def save_sync_missing_packages_cursor(cursor)
      metadata = @registry.metadata.to_h
      if cursor.present?
        metadata[SYNC_MISSING_CURSOR_KEY] = cursor
      else
        metadata.delete(SYNC_MISSING_CURSOR_KEY)
      end
      @registry.update!(metadata: metadata)
    end

    def license_for(model)
      card_data = model["cardData"]
      return card_data["license"] if card_data.is_a?(Hash) && card_data["license"].present?

      Array(model["tags"]).find { |tag| tag.start_with?("license:") }&.delete_prefix("license:")
    end

    def encoded_model_name(name)
      name.to_s.split("/").map { |segment| CGI.escape(segment) }.join("/")
    end

    def catalogue_url
      "#{API_URL}?limit=#{PAGE_SIZE}&sort=createdAt&direction=1"
    end
  end
end
