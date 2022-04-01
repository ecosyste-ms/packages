class HomeController < ApplicationController
  def index
    @registries = Registry.order('packages_count desc').all
  end
end