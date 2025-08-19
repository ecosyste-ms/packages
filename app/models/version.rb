class Version < ApplicationRecord
  include EcosystemsApiClient
  
  validates_presence_of :package_id, :number
  validates_uniqueness_of :number, scope: :package_id, case_sensitive: false

  belongs_to :package
  belongs_to :registry, optional: true
  counter_culture :package
  has_many :dependencies, dependent: :delete_all
  has_many :runtime_dependencies, -> { where kind: %w[runtime normal] }, class_name: "Dependency"

  scope :created_after, ->(created_at) { where('created_at > ?', created_at) }
  scope :published_after, ->(published_at) { where('published_at > ?', published_at) }
  scope :published_before, ->(published_at) { where('published_at < ?', published_at) }
  scope :updated_after, ->(updated_at) { where('updated_at > ?', updated_at) }
  scope :created_before, ->(created_at) { where('created_at < ?', created_at) }
  scope :updated_before, ->(updated_at) { where('updated_at < ?', updated_at) }

  scope :active, -> { where(status: nil) }

  def to_param
    number.gsub(/(\r\n|\n)/, "%0A")
  end

  def download_url
    package.registry.ecosystem_instance.download_url(package, self)
  end

  def install_command
    package.registry.ecosystem_instance.install_command(package, number)
  end

  def registry_url
    package.registry.ecosystem_instance.registry_url(package, self)
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
      ecosystems_api_get(archive_list_url) || []
    rescue
      []
    end
  end

  def archive_contents(path)
    return {} unless download_url.present?

    begin
      ecosystems_api_get(archive_contents_url(path)) || {}
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

  def related_versions
    @related_versions ||= package.try(:versions).try(:sort)
  end

  def version_index
    related_versions.index(self)
  end

  def next_version
    related_versions[version_index - 1]
  end

  def previous_version
    related_versions[version_index + 1]
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

  def update_integrity_async
    return if integrity.present?
    return if download_url.blank?
    UpdateIntegrityWorker.perform_async(id)
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
      ecosystems_api_get(digest_url) || {}
    rescue
      {}
    end
  end

  def purl
    package.registry.ecosystem_instance.purl(package, self)
  end

  def digest_url
    "https://digest.ecosyste.ms/digest?url=#{CGI.escape(download_url)}&encoding=hex&algorithm=sha256" # TODO encoding and algorithm should come from ecosystem_instance
  end

  def diff_url(other_version)
    if [other_version, self].sort.first == self
      url_1 = CGI.escape(other_version.download_url)
      url_2 = CGI.escape(download_url)
    else
      url_1 = CGI.escape(download_url)
      url_2 = CGI.escape(other_version.download_url)
    end
    "https://diff.ecosyste.ms/diff?url_1=#{url_1}&url_2=#{url_2}"
  end

  def compare_url
    return unless related_tag && related_tag['download_url'].present?
    return unless download_url.present?
    return if related_tag['download_url'] == download_url
    "https://diff.ecosyste.ms/diff?url_1=#{download_url}&url_2=#{related_tag['download_url']}"
  end

  def related_tag
    return unless package.repo_metadata && package.repo_metadata['tags'] && package.repo_metadata['tags'].is_a?(Array)
    package.repo_metadata['tags'].find { |tag| tag['name'].delete_prefix('v') == number.delete_prefix('v') }
  end

  def valid_number?
    !!semantic_version
  end

  def stable?
    valid_number? && !prerelease?
  end

  def prerelease?
    if semantic_version && semantic_version.pre.present?
      true
    else
      case package.try(:ecosystem)
      when "rubygems"
        !!number[/[a-zA-Z]/]
      when "pypi"
        !!(number =~ /(a|b|rc|dev)[-_.]?[0-9]*$/)
      else
        false
      end
    end
  end

  def transitive_dependencies(max_depth: TransitiveDependencyResolver::DEFAULT_MAX_DEPTH, max_dependencies: TransitiveDependencyResolver::DEFAULT_MAX_DEPENDENCIES, include_optional: false, kind: nil)
    resolver = TransitiveDependencyResolver.for_ecosystem(package.ecosystem).new(
      self,
      max_depth: max_depth,
      max_dependencies: max_dependencies,
      include_optional: include_optional,
      kind: kind
    )
    resolver.resolve
  end
end
