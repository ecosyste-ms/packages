class FundingController < ApplicationController
  def index
    @registries = Registry.all.sort_by{|r| -r.funded_packages_count }
  end

  def show
    @registry = Registry.find_by!(name: params[:id])
    @pagy, @packages = pagy_countless(@registry.packages.with_funding.active.order(Arel.sql("(rankings->>'average')::text::float").asc))
  end

  def platforms
    @registries = Registry.all.sort_by{|r| -r.funded_packages_count }
    scope = Package.with_funding.active
    @domains = Rails.cache.fetch("funding:domains", expires_in: 1.week) do
      scope.map{|p| p.funding_domains}.flatten.group_by(&:itself).map{|k, v| [k, v.count]}.to_h.sort_by{|k, v| v}.reverse.to_h
    end
  end
end