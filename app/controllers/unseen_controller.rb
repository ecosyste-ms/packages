class UnseenController < ApplicationController
  def index
    @ecosystems = ['cargo','hackage','hex','homebrew','npm','nuget','packagist','puppet','rubygems','pypi']
    @registries = Registry.where(ecosystem: @ecosystems).order('packages_count DESC')
  end

  def ecosystem
    @ecosystem = params[:ecosystem]
    @registry = Registry.where(ecosystem: @ecosystem).first
    @scope = @registry.packages.with_repo_metadata.order('downloads DESC').where('downloads > ?', 100_000).where("(repo_metadata ->> 'stargazers_count')::text::integer < 100")
    @pagy, @packages = pagy_countless(@scope)
  end
end