class TopController < ApplicationController
  def index
    @ecosystems = Registry.order('packages_count desc').uniq(&:ecosystem)
  end

  def ecosystem
    @registry = Registry.find_by_ecosystem(params[:ecosystem])

    @scope = @registry.packages.where('versions_count > 0 and (status is null or status != ?)', 'removed')

    case params[:sort]  
    when 'downloads'
      @sort_name = 'downloads'
      @sort = 'downloads desc nulls last' 
    when 'dependent_packages_count'
      @sort_name = 'dependent packages'
      @sort = 'dependent_packages_count desc nulls last'
    when 'dependent_repos_count'
      @sort_name = 'dependent repos'
      @sort = 'dependent_repos_count desc nulls last'
    when 'stars'
      @sort_name = 'stars'
      @sort = Arel.sql("(repo_metadata ->> 'stargazers_count')::text::integer").desc.nulls_last
    when 'forks'
      @sort_name = 'forks'
      @sort = Arel.sql("(repo_metadata ->> 'forks_count')::text::integer").desc.nulls_last
    when 'versions_count'
      @sort_name = 'versions'
      @sort = 'versions_count desc nulls last'      
    when 'maintainers_count'
      @sort_name = 'maintainers'
      @sort = 'maintainers_count desc nulls last'
    when 'latest_release_published_at'
      @sort_name = 'latest release'
      @sort = 'latest_release_published_at desc nulls last'
      @scope = @scope.top(1)
    else
      @sort_name = 'average ranking'
      @sort = Arel.sql("(rankings->>'average')::text::float").asc.nulls_last
    end

    @packages = @scope.order(@sort).limit(200)
  end
end