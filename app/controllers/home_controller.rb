class HomeController < ApplicationController
  def index
    @recent_versions = Version.where('published_at > ?', 2.months.ago).group_by_day(:published_at).count
    @registries = Registry.order('packages_count desc').all
  end
end