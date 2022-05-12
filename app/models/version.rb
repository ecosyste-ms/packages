class Version < ApplicationRecord
  validates_presence_of :package_id, :number
  validates_uniqueness_of :number, scope: :package_id, case_sensitive: false

  belongs_to :package
  counter_culture :package
  has_many :dependencies, -> { order('package_name asc') }, dependent: :delete_all
  has_many :runtime_dependencies, -> { where kind: %w[runtime normal] }, class_name: "Dependency"

  def download_url
    package.registry.ecosystem_instance.download_url(package, self)
  end

  def install_command
    package.registry.ecosystem_instance.install_command(package, number)
  end

  def registry_url
    package.registry.ecosystem_instance.registry_url(package, number)
  end

  def documentation_url
    package.registry.ecosystem_instance.documentation_url(package, number)
  end

  def published_at
    @published_at ||= read_attribute(:published_at).presence || created_at
  end

  def archive_list
    return [] unless download_url.present?

    begin
      Oj.load(Faraday.get(archive_list_url).body)
    rescue
      []
    end
  end

  def archive_contents(path)
    return {} unless download_url.present?

    begin
      Oj.load(Faraday.get(archive_contents_url(path)).body)
    rescue
      {}
    end
  end

  def archive_list_url
    "https://archives.ecosyste.ms/api/v1/archives/list?url=#{CGI.escape(download_url)}"
  end

  def archive_contents_url(path)
    "https://archives.ecosyste.ms/api/v1/archives/contents?url=#{CGI.escape(download_url)}&path=#{path}"
  end

  def archive_basename
    File.basename(download_url)
  end

  def <=>(other)
    if parsed_number.is_a?(String) || other.parsed_number.is_a?(String)
      other.published_at <=> published_at
    else
      begin
        other.parsed_number <=> parsed_number
      rescue ArgumentError
        other.published_at <=> published_at
      end
    end
  end

  def to_s
    number
  end

  def semantic_version
    @semantic_version ||= begin
      Semantic::Version.new(clean_number)
    rescue ArgumentError
      nil
    end
  end

  def parsed_number
    @parsed_number ||= semantic_version || number
  end

  def clean_number
    @clean_number ||= (SemanticRange.clean(number) || number)
  end

  def update_integrity
    return if integrity.present?
    return if download_url.blank?

    update(integrity: calculate_integrity['sri'])
  end

  def check_integrity
    return if integrity.blank?
    return if download_url.blank?

    calculate_integrity['sri'] == integrity
  end

  def calculate_integrity
    begin
      Oj.load(Faraday.get(digest_url).body)
    rescue
      {}
    end
  end

  def digest_url
    "https://digest.ecosyste.ms/digest?url=#{CGI.escape(download_url)}&encoding=hex&algorithm=sha256" # TODO encoding and algorithm should come from ecosystem_instance
  end
end
