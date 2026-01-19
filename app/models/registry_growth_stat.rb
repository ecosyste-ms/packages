class RegistryGrowthStat < ApplicationRecord
  MIN_YEAR = 2005

  validates_presence_of :registry_id, :year
  validates_uniqueness_of :year, scope: :registry_id

  belongs_to :registry

  scope :by_year, -> { order(year: :asc) }
  scope :from_min_year, -> { where("year >= ?", MIN_YEAR) }

  def self.years_range
    minimum(:year)..maximum(:year)
  end

  def packages_growth_rate
    return nil if previous_stat.nil? || previous_stat.packages_count.zero?
    ((packages_count - previous_stat.packages_count).to_f / previous_stat.packages_count * 100).round(2)
  end

  def versions_growth_rate
    return nil if previous_stat.nil? || previous_stat.versions_count.zero?
    ((versions_count - previous_stat.versions_count).to_f / previous_stat.versions_count * 100).round(2)
  end

  def previous_stat
    @previous_stat ||= RegistryGrowthStat.find_by(registry_id: registry_id, year: year - 1)
  end
end
