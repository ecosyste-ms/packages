class HomeController < ApplicationController
  def index
    @registries = Registry.order('packages_count desc').all
    fresh_when(@registries, public: true)
  end

  def recent_versions_data
    @recent_versions = Rails.cache.fetch("all_recent_versions_data", expires_in: 1.day) do
      Version.where('published_at > ?', 1.months.ago.beginning_of_day).where('published_at < ?', 1.day.ago.end_of_day).group_by_day(:published_at).count
    end
    if stale?(@recent_versions, public: true)
      render json: @recent_versions
    end
  end
end