class Maintainer < ApplicationRecord
  TOMBSTONE_PACKAGES_COUNT = -1

  belongs_to :registry
  counter_culture :registry
  has_many :maintainerships, dependent: :delete_all
  has_many :packages, through: :maintainerships

  def self.sortable_columns
    {
      'packages_count' => 'packages_count',
      'login' => 'login',
      'name' => 'name',
      'uuid' => 'uuid',
      'updated_at' => 'updated_at',
      'created_at' => 'created_at',
    }
  end

  validates :uuid, presence: true, uniqueness: {scope: :registry_id}

  scope :created_after, ->(created_at) { where('created_at > ?', created_at) }
  scope :updated_after, ->(updated_at) { where('updated_at > ?', updated_at) }
  scope :hidden, -> { where(packages_count: TOMBSTONE_PACKAGES_COUNT) }
  scope :visible, -> { where('packages_count IS NULL OR packages_count >= 0') }
  scope :matching_identity, ->(identifiers) do
    identifiers = Array(identifiers).compact.map { |identifier| identifier.to_s.downcase }.reject(&:blank?).uniq
    identifiers.empty? ? none : where('LOWER(uuid) IN (:identifiers) OR LOWER(login) IN (:identifiers)', identifiers: identifiers)
  end

  attr_accessor :role

  def to_param
    login.presence || uuid
  end

  def to_s
    name.presence || login.presence || uuid
  end

  def update_packages_count 
    return if hidden?
    update_column(:packages_count, packages.count)
  end

  def update_total_downloads
    return if hidden?
    update_column(:total_downloads, packages.sum(:downloads))
  end

  def hide!
    self.class.transaction do
      update!(packages_count: TOMBSTONE_PACKAGES_COUNT, total_downloads: 0, email: nil, name: nil, url: nil, organization: nil)

      maintainerships.in_batches do |batch|
        package_ids = batch.pluck(:package_id)
        batch.delete_all
        Package.where(id: package_ids).find_each(&:update_maintainers_count)
      end
    end
  end

  def hidden?
    packages_count == TOMBSTONE_PACKAGES_COUNT
  end

  def html_url
    registry.maintainer_url(self)
  end

  def namespaces
    packages.where.not(namespace: nil).group(:namespace).order('COUNT(packages.id) desc').count.to_a
  end
end
