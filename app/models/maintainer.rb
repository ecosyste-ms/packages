class Maintainer < ApplicationRecord
  belongs_to :registry
  has_many :maintainerships
  has_many :packages, through: :maintainerships

  def to_param
    login
  end

  def to_s
    name.presence || login.presence || uuid
  end

  def update_packages_count 
    update(packages_count: packages.count)
  end
end
