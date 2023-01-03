class FundingController < ApplicationController
  def index
    @registries = Registry.all.sort_by{|r| -r.funded_packages_count }
  end

  def show
    @registry = Registry.find_by!(name: params[:id])
    @pagy, @packages = pagy_countless(@registry.packages.with_funding.active.order(Arel.sql("(rankings->>'average')::text::float").asc))
  end
end