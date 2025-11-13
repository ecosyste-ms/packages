class InfrastructureController < ApplicationController
  def index
    @scope = Package.includes(:registry).active.top(1.05).order(Arel.sql("(rankings->>'average')::text::float").asc).limit(10_000)

    @all_registries = Registry.all
    @registry_ids = Rails.cache.fetch("infrastructure_registry_counts", expires_in: 1.hour) do
      @scope.pluck(:registry_id).tally
    end
    @registries = @registry_ids.map{|id, count| [@all_registries.find{|r| r.id == id}, count]}.sort_by{|r, count| -count}

    if params[:registry]
      @registry = Registry.find_by_name!(params[:registry])
      @scope = @scope.where(registry_id: @registry.id)
    end

    @pagy, @packages = pagy_countless(@scope)
  end
end