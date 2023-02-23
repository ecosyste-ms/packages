class TopController < ApplicationController
  def index
    @ecosystems = Registry.order('packages_count desc').uniq(&:ecosystem)
  end

  def ecosystem
    @registry = Registry.find_by_ecosystem(params[:ecosystem])

    case params[:sort]  
    when 'downloads'
      @sort = 'downloads desc nulls last' 
    when 'dependent_packages_count'
      @sort = 'dependent_packages_count desc nulls last'
    when 'dependent_repos_count'
      @sort = 'dependent_repos_count desc nulls last'
    when 'stars'
      @sort = Arel.sql("(repo_metadata ->> 'stargazers_count')::text::integer").desc.nulls_last
    when 'forks'
      @sort = Arel.sql("(repo_metadata ->> 'forks_count')::text::integer").desc.nulls_last
    when 'versions_count'
      @sort = 'versions_count desc nulls last'      
    when 'maintainers_count'
      @sort = 'maintainers_count desc nulls last'
    else
      @sort = Arel.sql("(rankings->>'average')::text::float").asc.nulls_last
    end

    @packages = @registry.packages.where('versions_count > 0 and (status is null or status != ?)', 'removed').order(@sort).limit(200)
  end
end