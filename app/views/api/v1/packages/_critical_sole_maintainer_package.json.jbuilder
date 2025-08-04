json.extract! package, :id, :name, :ecosystem, :description, :homepage, :licenses, :normalized_licenses, :repository_url, :keywords_array, :namespace, :versions_count, :first_release_published_at, :latest_release_published_at, :latest_release_number, :last_synced_at, :created_at, :updated_at, :registry_url, :install_command, :documentation_url, :metadata, :repo_metadata, :repo_metadata_updated_at, :dependent_packages_count, :downloads, :downloads_period, :dependent_repos_count, :rankings, :purl, :advisories, :docker_usage_url, :docker_dependents_count, :docker_downloads_count, :usage_url, :dependent_repositories_url, :status, :funding_links, :critical, :issue_metadata

json.versions_url api_v1_registry_package_versions_url(registry_id: package.registry.name, package_id: package.name)
json.version_numbers_url version_numbers_api_v1_registry_package_url(registry_id: package.registry.name, id: package.name)
json.dependent_packages_url dependent_packages_api_v1_registry_package_url(registry_id: package.registry.name, id: package.name)
json.related_packages_url related_packages_api_v1_registry_package_url(registry_id: package.registry.name, id: package.name)

json.maintainers package.maintainerships.select{|m| m.maintainer.present? }, partial: 'api/v1/maintainerships/maintainership', as: :maintainership
json.maintainers_count package.maintainers_count

json.registry do
  json.extract! package.registry, :id, :name, :ecosystem, :url, :metadata
end

if package.issue_metadata.present?
  json.repository_activity do
    json.contributors do
      json.past_year_committers_count package.issue_metadata['past_year_committers_count'].to_i if package.issue_metadata['past_year_committers_count'].present?
      json.past_year_issue_authors_count package.issue_metadata['past_year_issue_authors_count'].to_i if package.issue_metadata['past_year_issue_authors_count'].present?
      json.past_year_pull_request_authors_count package.issue_metadata['past_year_pull_request_authors_count'].to_i if package.issue_metadata['past_year_pull_request_authors_count'].present?
    end
    
    json.issues_and_prs do
      json.past_year_issues_count package.issue_metadata['past_year_issues_count'].to_i if package.issue_metadata['past_year_issues_count'].present?
      json.past_year_pull_requests_count package.issue_metadata['past_year_pull_requests_count'].to_i if package.issue_metadata['past_year_pull_requests_count'].present?
    end
    
    json.past_year_commits_count package.issue_metadata['past_year_commits_count'].to_i if package.issue_metadata['past_year_commits_count'].present?
    
    json.maintainer_analysis do
      if package.issue_metadata['maintainers'].present?
        json.total_maintainers package.issue_metadata['maintainers'].size
        json.maintainers_list package.issue_metadata['maintainers']
        if package.issue_metadata['maintainers'].first && package.issue_metadata['maintainers'].first['login'].present?
          json.primary_maintainer_login package.issue_metadata['maintainers'].first['login']
        end
      end
      
      if package.issue_metadata['active_maintainers'].present?
        json.active_maintainers_count package.issue_metadata['active_maintainers'].size
        json.active_maintainers_list package.issue_metadata['active_maintainers']
      end
      
      if package.issue_metadata['dds'].present?
        json.dds package.issue_metadata['dds'].to_f.round(3)
      end
    end
    
    json.funding do
      if package.funding_links.any?
        json.has_funding_links true
        json.funding_links_count package.funding_links.count
        json.funding_links package.funding_links
        json.primary_funding_link package.funding_links.first
      else
        json.has_funding_links false
        json.funding_links_count 0
      end
    end
  end
end