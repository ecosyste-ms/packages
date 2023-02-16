class TopController < ApplicationController
  def index
    @ecosystems = Registry.order('packages_count desc').uniq(&:ecosystem)
  end

  def ecosystem
    @registry = Registry.find_by_ecosystem(params[:ecosystem])
    @packages = @registry.packages.includes(:maintainers).order(Arel.sql("(rankings->>'average')::text::float").asc).limit(200)
  end
end