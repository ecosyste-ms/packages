class Version < ApplicationRecord
  validates_presence_of :package_id, :number
  validates_uniqueness_of :number, scope: :package_id, case_sensitive: false

  belongs_to :package
  counter_culture :package
  has_many :dependencies, -> { order('package_name asc') }, dependent: :delete_all
  has_many :runtime_dependencies, -> { where kind: %w[runtime normal] }, class_name: "Dependency"

  def download_url
    package.registry.ecosystem_instance.download_url(package.name, number)
  end

  def install_command
    package.registry.ecosystem_instance.install_command(package, number)
  end

  def registry_url
    package.registry.ecosystem_instance.registry_url(package, number)
  end

  def documentation_url
    package.registry.ecosystem_instance.documentation_url(package.name, number)
  end

  def published_at
    @published_at ||= read_attribute(:published_at).presence || created_at
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
end
