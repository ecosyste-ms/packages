class FundingController < ApplicationController
  def index
    @registries = Registry.all.sort_by{|r| -r.metadata['funded_packages_count'] }
  end

  def show
    @registry = Registry.find_by!(name: params[:id])
    @pagy, @packages = pagy(@registry.packages.with_funding.active)
  end
end