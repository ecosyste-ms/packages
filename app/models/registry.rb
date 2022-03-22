class Registry < ApplicationRecord
  validates_presence_of :name, :url, :ecosystem

  validates_uniqueness_of :name, :url

  has_many :packages
  has_many :versions, through: :packages

  def all_package_names
    ecosystem_instance.all_package_names
  end

  def recently_updated_package_names
    ecosystem_instance.recently_updated_package_names
  end

  # get list of recently updated package names (and/or versions?)
  # sync a package by name
  # sync a single version of a package

  def ecosystem_instance
    @ecosystem_instance ||= ecosystem_class.new(url)
  end

  def ecosystem_class
    Ecosystem::Base.find(ecosystem)
  end
end
