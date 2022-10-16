class InfrastructureController < ApplicationController
  def index
    scope = Package.order(Arel.sql("(rankings->'average')::text::float").asc.nulls_last).limit(10_000)

    @registry_ids = scope.pluck(:registry_id).tally
    @registries = @registry_ids.map{|id, count| [Registry.find(id), count]}.sort_by{|r, count| -count}

    if params[:registry]
      @registry = Registry.find_by!(name: params[:registry])
      scope = scope.where(registry_id: @registry.id)
    end

    @pagy, @packages = pagy(scope)
  end
end