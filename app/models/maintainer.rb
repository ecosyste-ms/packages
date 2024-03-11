class Maintainer < ApplicationRecord
  belongs_to :registry
  counter_culture :registry
  has_many :maintainerships, dependent: :delete_all
  has_many :packages, through: :maintainerships

  validates :uuid, presence: true, uniqueness: {scope: :registry_id}

  scope :created_after, ->(created_at) { where('created_at > ?', created_at) }
  scope :updated_after, ->(updated_at) { where('updated_at > ?', updated_at) }

  attr_accessor :role

  def to_param
    login.presence || uuid
  end

  def to_s
    name.presence || login.presence || uuid
  end

  def update_packages_count 
    update(packages_count: packages.count)
  end

  def update_total_downloads
    update(total_downloads: packages.sum(:downloads))
  end

  def html_url
    registry.maintainer_url(self)
  end

  def namespaces
    packages.where.not(namespace: nil).group(:namespace).order('COUNT(packages.id) desc').count.to_a
  end
end
