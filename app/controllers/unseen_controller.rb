class UnseenController < ApplicationController
  def index
    @scope = Package.includes(:registry).with_repo_metadata.order('packages.downloads DESC').where('packages.downloads > ?', 100_000).where("(repo_metadata ->> 'stargazers_count')::text::integer < 100")

    @all_registries = Registry.all
    @registry_ids = @scope.pluck(:registry_id).tally
    @registries = @registry_ids.map{|id, count| [@all_registries.find{|r| r.id == id}, count]}.compact.reject{|r, count| r.nil?}.sort_by{|r, count| -count}

    if params[:registry]
      @registry = Registry.find_by_name!(params[:registry])
      @scope = @scope.where(registry_id: @registry.id)
    end

    @pagy, @packages = pagy_countless(@scope)
  end

  def ecosystem
    @ecosystem = params[:ecosystem]
    @registry = Registry.find_by(ecosystem: @ecosystem) || Registry.find_by(name: @ecosystem)
    raise ActiveRecord::RecordNotFound, "Registry with ecosystem or name '#{@ecosystem}' not found" if @registry.nil?
    redirect_to unseen_path(registry: @registry.name)
  end
end