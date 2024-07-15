class UnderproductionController < ApplicationController
  def index
    @registries = Registry.all.sort_by{|r| -r.packages_count }
  end

  def show
    @registry = Registry.find_by_name!(params[:id])
    @pagy, @packages = pagy_countless(@registry.packages.production.order(Arel.sql("(rankings->'underproduction'->>'production')::text::float").desc))
  end
end