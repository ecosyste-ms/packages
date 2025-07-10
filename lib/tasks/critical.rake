namespace :critical do
  desc "Download critical packages from production API and store in database"
  task download: :environment do
    puts "Downloading critical packages by registry..."
    total_downloaded = 0
    
    Registry.find_each do |registry|
      puts "Processing registry: #{registry.name}"
      downloaded = download_critical_packages_for_registry(registry)
      total_downloaded += downloaded
      puts "Downloaded #{downloaded} critical packages from #{registry.name}"
    end
    
    puts "Finished downloading #{total_downloaded} total critical packages"
  end
  
  def download_critical_packages_for_registry(registry)
    url = "https://packages.ecosyste.ms/api/v1/registries/#{registry.name}/packages"
    page = 1
    downloaded_count = 0
    
    puts "  Fetching from: #{url}?critical=true&page=1&per_page=100"
    
    loop do
      response = Package.ecosystems_api_get(url, params: { 
        critical: true, 
        page: page, 
        per_page: 100 
      })
      
      puts "  Page #{page}: Got #{response&.size || 'nil'} packages"
      
      break unless response && response.is_a?(Array) && response.any?
      
      response.each do |package_data|
        download_package(package_data, registry)
        downloaded_count += 1
      end
      
      page += 1
      break if response.size < 100
    end
    
    downloaded_count
  end
  
  def download_package(package_data, registry)
    # Find or create package
    package = Package.find_or_create_by(
      registry: registry,
      name: package_data['name']
    ) do |p|
      p.ecosystem = package_data['ecosystem']
    end
    
    # Update package with critical data (safely handle nil values)
    update_data = {
      critical: true,
      status: nil,
      downloads: package_data['downloads'],
      dependent_packages_count: package_data['dependent_packages_count'],
      dependent_repos_count: package_data['dependent_repos_count'],
      repository_url: package_data['repository_url'],
      homepage: package_data['homepage'],
      description: package_data['description'],
      keywords: package_data['keywords'] || [],
      latest_release_number: package_data['latest_release_number'],
      maintainers_count: Array(package_data['maintainers']).size,
      versions_count: package_data['versions_count'],
      metadata: package_data['metadata'] || {},
      repo_metadata: package_data['repo_metadata'] || {},
      issue_metadata: package_data['issue_metadata'] || {}
    }
    
    # Handle date field safely
    if package_data['latest_release_published_at'].present?
      update_data[:latest_release_published_at] = package_data['latest_release_published_at']
    end
    
    package.update!(update_data)
    
    puts "  Downloaded: #{package_data['name']} (maintainers: #{Array(package_data['maintainers']).size})"
  rescue => e
    puts "  Error downloading #{package_data['name']}: #{e.message}"
  end
end