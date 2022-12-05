class InfrastructureController < ApplicationController
  def index
    @scope = Package.includes(:registry).active.top.order(Arel.sql("(rankings->>'average')::text::float").asc).limit(10_000)

    @all_registries = Registry.all
    @registry_ids = @scope.pluck(:registry_id).tally
    @registries = @registry_ids.map{|id, count| [@all_registries.find{|r| r.id == id}, count]}.sort_by{|r, count| -count}

    if params[:registry]
      @registry = Registry.find_by!(name: params[:registry])
      @scope = @scope.where(registry_id: @registry.id)
    end

    @pagy, @packages = pagy(@scope)
  end
end