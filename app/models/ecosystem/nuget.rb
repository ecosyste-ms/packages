# frozen_string_literal: true

module Ecosystem
  class Nuget < Base
    def registry_url(package, version = nil)
      "#{@registry_url}/packages/#{package.name}/#{version}"
    end

    def download_url(package, version)
      return nil unless version.present?
      "https://api.nuget.org/v3-flatcontainer/#{package.name.downcase}/#{version}/#{package.name.downcase}.#{version}.nupkg"
    end

    def install_command(package, version = nil)
      "Install-Package #{package.name}" + (version ? " -Version #{version}" : "")
    end

    def check_status_url(package)
      "https://api.nuget.org/v3-flatcontainer/#{package.name.downcase}/index.json"
    end

    def check_status(package)
      url = check_status_url(package)
      response = Faraday.get(url)
      return "removed" if [400, 404, 410].include?(response.status)

      url = registry_url(package)
      response = Faraday.get(url)
      return "removed" if [400, 404, 410].include?(response.status)
      return "removed" if response.body.include? 'This package has been deleted from the gallery.'
      return "removed" if response.body.include? "This package's content is hidden"

      return "deprecated" if all_versions_deprecated?(package)
    rescue Faraday::Error => e
      nil
    end

    def all_versions_deprecated?(package)
      releases = get_releases(package.name)
      return false if releases.blank?

      listed_releases = releases.select { |r| r.dig("catalogEntry", "listed") != false }
      return false if listed_releases.blank?

      listed_releases.all? { |r| r.dig("catalogEntry", "deprecation").present? }
    rescue StandardError
      false
    end

    def recently_updated_package_names
      name_endpoints.reverse[0..1].map { |url| get_names(url) }.flatten.uniq
    rescue
      []
    end

    def name_endpoints
      get("https://api.nuget.org/v3/catalog0/index.json")["items"].map { |i| i["@id"] }
    end

    def get_names(endpoint)
      get(endpoint)["items"].map { |i| i["nuget:id"] }
    end

    def all_package_names
      endpoints = name_endpoints
      segment_count = endpoints.length - 1

      names = []
      endpoints.reverse[0..segment_count].each do |endpoint|
        package_ids = get_names(endpoint)
        package_ids.each { |id| names << id.downcase }
      end
      return names
    rescue
      []
    end

    def fetch_package_metadata(name)
      h = {
        name: name,
      }
      h[:releases] = get_releases(name)
      h[:download_stats] = download_stats(name)
      h[:versions] = versions_metadata(h)
      
      return {} unless h[:versions].any?

      h
    end

    def download_stats(name)
      get_json("https://azuresearch-usnc.nuget.org/query?q=packageid:#{name.downcase}")
    rescue
      {}
    end

    def get_releases(name)
      latest_version = get_json("https://api.nuget.org/v3/registration5-gz-semver2/#{name.downcase}/index.json")
      if latest_version["items"][0]["items"]
        releases = []
        latest_version["items"].each do |items|
          releases << items["items"]
        end
        releases.flatten!
      elsif releases.nil?
        releases = []
        latest_version["items"].each do |page|
          json = get_json(page["@id"])
          releases << json["items"]
        end
        releases.flatten!
      end
      releases
    rescue StandardError
      []
    end

    def map_package_metadata(package)
      return false if package[:releases].nil?
      item = package[:releases].last["catalogEntry"]

      # Get comprehensive nuspec metadata for the latest version
      nuspec_metadata = parse_nuspec_metadata(package[:name], item["version"])

      {
        name: package[:name].try(:downcase),
        description: description(item),
        homepage: item["projectUrl"],
        keywords_array: Array(item["tags"]).reject(&:blank?),
        repository_url: repo_fallback(item["projectUrl"], item["licenseUrl"], item["packageUrl"], 
                                    package_name: package[:name], version: item["version"]),
        releases: package[:releases],
        licenses: item["licenseExpression"],
        downloads: package[:download_stats]['data'].try(:first).try(:fetch,'totalDownloads'),
        downloads_period: 'total',
        download_stats: package[:download_stats],
        
        # Enhanced metadata from .nuspec file
        metadata: build_package_nuspec_metadata(nuspec_metadata, package)
      }
    end

    def build_package_nuspec_metadata(nuspec_metadata, package)
      # Only include NuGet-specific fields that aren't duplicates of standard package fields
      return {} unless nuspec_metadata

      metadata = {
        # NuGet-specific package information
        copyright: nuspec_metadata[:copyright],
        owners: nuspec_metadata[:owners],
        
        # Legal and licensing (detailed)
        license_info: nuspec_metadata[:license],
        license_url: nuspec_metadata[:license_url],
        require_license_acceptance: nuspec_metadata[:require_license_acceptance],
        
        # URLs and resources (NuGet-specific)
        icon_url: nuspec_metadata[:icon_url],
        icon: nuspec_metadata[:icon],
        readme: nuspec_metadata[:readme],
        
        # Repository details (more detailed than just URL)
        repository: nuspec_metadata[:repository],
        
        # Technical information
        min_client_version: nuspec_metadata[:min_client_version],
        language: nuspec_metadata[:language],
        development_dependency: nuspec_metadata[:development_dependency],
        serviceable: nuspec_metadata[:serviceable],
        
        # Framework and packaging information
        framework_assemblies: nuspec_metadata[:framework_assemblies],
        package_types: nuspec_metadata[:package_types],
        
        # Additional categorization
        summary: nuspec_metadata[:summary],
        release_notes: nuspec_metadata[:release_notes]
      }.compact
      
      # Only include dependency information if it exists
      if nuspec_metadata[:dependency_groups]&.any?
        metadata[:dependency_summary] = {
          total_dependency_groups: nuspec_metadata[:dependency_groups].length,
          target_frameworks: nuspec_metadata[:dependency_groups].map { |g| g[:target_framework] }.compact.uniq,
          total_dependencies: nuspec_metadata[:dependency_groups].sum { |g| g[:dependencies]&.length || 0 }
        }
      end
      
      metadata
    end

    def repo_fallback(repo, license, homepage, package_name: nil, version: nil)
      repo = "" if repo.nil?
      homepage = "" if homepage.nil?
      license = "" if license.nil?
      repo_url = UrlParser.try_all(repo) rescue ""
      homepage_url = UrlParser.try_all(homepage) rescue ""
      license_url = UrlParser.try_all(license) rescue ""
      if repo_url.present?
        repo_url
      elsif homepage_url.present?
        homepage_url
      elsif license_url.present?
        license_url
      else
        # Fallback to .nuspec file parsing if API URLs don't contain repository info
        nuspec_repo_url(package_name, version) if package_name && version
      end
    end

    def nuspec_repo_url(package_name, version)
      nuspec_metadata = parse_nuspec_metadata(package_name, version)
      return "" unless nuspec_metadata
      
      repository_url = nuspec_metadata.dig(:repository, :url)
      return UrlParser.try_all(repository_url) if repository_url.present?
      ""
    end

    def parse_nuspec_metadata(package_name, version)
      return nil unless package_name && version
      
      nuspec_url = "https://api.nuget.org/v3-flatcontainer/#{package_name.downcase}/#{version}/#{package_name.downcase}.nuspec"
      response = Faraday.get(nuspec_url)
      return nil unless response.success?
      
      # Parse XML to extract comprehensive metadata
      require 'nokogiri'
      doc = Nokogiri::XML(response.body)
      
      # Remove namespace for easier querying
      doc.remove_namespaces!
      metadata_node = doc.at_xpath('//metadata')
      return nil unless metadata_node
      
      # Extract comprehensive metadata
      {
        # Basic package information
        id: metadata_node.at_xpath('id')&.text,
        version: metadata_node.at_xpath('version')&.text,
        title: metadata_node.at_xpath('title')&.text,
        authors: metadata_node.at_xpath('authors')&.text,
        owners: metadata_node.at_xpath('owners')&.text,
        
        # License and legal information
        license: extract_license_info(metadata_node),
        license_url: metadata_node.at_xpath('licenseUrl')&.text,
        require_license_acceptance: metadata_node.at_xpath('requireLicenseAcceptance')&.text == 'true',
        copyright: metadata_node.at_xpath('copyright')&.text,
        
        # URLs and resources
        project_url: metadata_node.at_xpath('projectUrl')&.text,
        icon_url: metadata_node.at_xpath('iconUrl')&.text,
        icon: metadata_node.at_xpath('icon')&.text,
        readme: metadata_node.at_xpath('readme')&.text,
        
        # Description and categorization
        description: metadata_node.at_xpath('description')&.text,
        summary: metadata_node.at_xpath('summary')&.text,
        tags: metadata_node.at_xpath('tags')&.text,
        release_notes: metadata_node.at_xpath('releaseNotes')&.text,
        
        # Repository information
        repository: extract_repository_info(metadata_node),
        
        # Technical metadata
        min_client_version: metadata_node.attr('minClientVersion'),
        language: metadata_node.at_xpath('language')&.text,
        development_dependency: metadata_node.at_xpath('developmentDependency')&.text == 'true',
        serviceable: metadata_node.at_xpath('serviceable')&.text == 'true',
        
        # Dependencies information (detailed)
        dependency_groups: extract_dependency_groups(metadata_node),
        
        # Framework information
        framework_assemblies: extract_framework_assemblies(metadata_node),
        content_files: extract_content_files(metadata_node),
        package_types: extract_package_types(metadata_node),
        
        # Additional metadata
        raw_xml: response.body # Store raw XML for any future parsing needs
      }
    rescue => e
      Rails.logger.debug "Failed to parse .nuspec for #{package_name} v#{version}: #{e.message}"
      nil
    end

    def description(item)
      item["description"].blank? ? item["summary"] : item["description"]
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkg_metadata[:releases].map do |item|
        catalog_entry = item["catalogEntry"]
        version = catalog_entry["version"]
        status = version_status(catalog_entry)

        {
          number: version,
          published_at: catalog_entry["published"],
          status: status,
          metadata: build_version_nuspec_metadata(pkg_metadata[:name], version, pkg_metadata, item)
        }
      end
    end

    def version_status(catalog_entry)
      return "deprecated" if catalog_entry["deprecation"].present?
      return "unlisted" if catalog_entry["listed"] == false
      nil
    end

    def build_version_nuspec_metadata(package_name, version, pkg_metadata, item)
      catalog_entry = item["catalogEntry"]

      # Start with basic API metadata
      base_metadata = {
        downloads: version_downloads(pkg_metadata, version),

        # From API catalogEntry
        api_description: catalog_entry["description"],
        api_summary: catalog_entry["summary"],
        api_title: catalog_entry["title"],
        api_authors: catalog_entry["authors"],
        api_license_expression: catalog_entry["licenseExpression"],
        api_license_url: catalog_entry["licenseUrl"],
        api_project_url: catalog_entry["projectUrl"],
        api_icon_url: catalog_entry["iconUrl"],
        api_tags: catalog_entry["tags"],
        api_min_client_version: catalog_entry["minClientVersion"],
        api_language: catalog_entry["language"],

        # Technical details from API
        package_content_url: item["packageContent"],
        catalog_entry_id: catalog_entry["@id"],
        listed: catalog_entry["listed"],
        require_license_acceptance: catalog_entry["requireLicenseAcceptance"],

        # Deprecation information from catalogEntry
        deprecation: catalog_entry["deprecation"]
      }
      
      # Get enhanced metadata from .nuspec file
      nuspec_metadata = parse_nuspec_metadata(package_name, version)
      return base_metadata unless nuspec_metadata
      
      # Merge with comprehensive .nuspec metadata
      base_metadata.merge({
        # Enhanced .nuspec fields
        nuspec_id: nuspec_metadata[:id],
        nuspec_title: nuspec_metadata[:title],
        nuspec_authors: nuspec_metadata[:authors],
        nuspec_owners: nuspec_metadata[:owners],
        nuspec_description: nuspec_metadata[:description],
        nuspec_summary: nuspec_metadata[:summary],
        nuspec_copyright: nuspec_metadata[:copyright],
        nuspec_tags: nuspec_metadata[:tags],
        nuspec_release_notes: nuspec_metadata[:release_notes],
        
        # License information (more detailed)
        license_info: nuspec_metadata[:license],
        
        # Repository information (detailed)
        repository: nuspec_metadata[:repository],
        
        # URLs and resources
        icon: nuspec_metadata[:icon],
        readme: nuspec_metadata[:readme],
        
        # Technical metadata
        min_client_version: nuspec_metadata[:min_client_version],
        language: nuspec_metadata[:language],
        development_dependency: nuspec_metadata[:development_dependency],
        serviceable: nuspec_metadata[:serviceable],
        
        # Dependency information (detailed for this version)
        dependency_groups: nuspec_metadata[:dependency_groups],
        framework_assemblies: nuspec_metadata[:framework_assemblies],
        content_files: nuspec_metadata[:content_files],
        package_types: nuspec_metadata[:package_types],
        
        # Analysis of differences between API and .nuspec
        metadata_source_comparison: {
          description_differs: (base_metadata[:api_description] != nuspec_metadata[:description]),
          title_differs: (base_metadata[:api_title] != nuspec_metadata[:title]),
          authors_differs: (base_metadata[:api_authors] != nuspec_metadata[:authors]),
          license_differs: (base_metadata[:api_license_expression] != nuspec_metadata[:license]&.dig(:text)),
          tags_differs: (base_metadata[:api_tags] != nuspec_metadata[:tags])
        }
      }).compact
    end

    def version_downloads(pkg_metadata, version)
      return nil unless pkg_metadata[:download_stats] && pkg_metadata[:download_stats]['data'].present?
      pkg_metadata[:download_stats]['data'][0]['versions'].find{|v| v['version'] == version}.try(:fetch,'downloads')
    rescue
      nil
    end

    private

    def extract_license_info(metadata_node)
      license_element = metadata_node.at_xpath('license')
      return nil unless license_element
      
      {
        type: license_element.attr('type'),
        text: license_element.text,
        version: license_element.attr('version')
      }
    end

    def extract_repository_info(metadata_node)
      repository_element = metadata_node.at_xpath('repository')
      return nil unless repository_element
      
      {
        type: repository_element.attr('type'),
        url: repository_element.attr('url'),
        branch: repository_element.attr('branch'),
        commit: repository_element.attr('commit')
      }
    end

    def extract_dependency_groups(metadata_node)
      dependency_groups = []
      metadata_node.xpath('dependencies/group').each do |group|
        target_framework = group.attr('targetFramework')
        dependencies = []
        
        group.xpath('dependency').each do |dep|
          dependencies << {
            id: dep.attr('id'),
            version: dep.attr('version'),
            include: dep.attr('include'),
            exclude: dep.attr('exclude')
          }
        end
        
        dependency_groups << {
          target_framework: target_framework,
          dependencies: dependencies
        }
      end
      dependency_groups
    end

    def extract_framework_assemblies(metadata_node)
      assemblies = []
      metadata_node.xpath('frameworkAssemblies/frameworkAssembly').each do |assembly|
        assemblies << {
          assembly_name: assembly.attr('assemblyName'),
          target_framework: assembly.attr('targetFramework')
        }
      end
      assemblies
    end

    def extract_content_files(metadata_node)
      files = []
      metadata_node.xpath('contentFiles/files/file').each do |file|
        files << {
          include: file.attr('include'),
          exclude: file.attr('exclude'),
          build_action: file.attr('buildAction'),
          copy_to_output: file.attr('copyToOutput'),
          flatten: file.attr('flatten')
        }
      end
      files
    end

    def extract_package_types(metadata_node)
      types = []
      metadata_node.xpath('packageTypes/packageType').each do |type|
        types << {
          name: type.attr('name'),
          version: type.attr('version')
        }
      end
      types
    end

    public

    def dependencies_metadata(_name, version, package)
      current_version = package[:releases].find { |v| v["catalogEntry"]["version"] == version }
      dep_groups = current_version.fetch("catalogEntry", {})["dependencyGroups"] || []

      deps = dep_groups.map do |dep_group|
        next unless dep_group["dependencies"]

        dep_group["dependencies"].map do |dependency|
          {
            name: dependency["id"],
            requirements: parse_requirements(dependency["range"]),
          }
        end
      end.flatten.compact

      deps.map do |dep|
        {
          package_name: dep[:name].downcase,
          requirements: dep[:requirements],
          kind: "runtime",
          optional: false,
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end

    def parse_requirements(range)
      return unless range.present?

      parts = range[1..-2].split(",")
      requirements = []
      low_bound = range[0]
      high_bound = range[-1]
      low_number = parts[0].strip
      high_number = parts[1].try(:strip)

      # lowest
      low_sign = low_bound == "[" ? ">=" : ">"
      high_sign = high_bound == "]" ? "<=" : "<"

      # highest
      if high_number != low_number
        requirements << "#{low_sign} #{low_number}" if low_number.present?
        requirements << "#{high_sign} #{high_number}" if high_number.present?
      elsif high_number == low_number
        requirements << "= #{high_number}"
      elsif low_number.present?
        requirements << "#{low_sign} #{low_number}"
      end
      requirements << ">= 0" if requirements.empty?
      requirements.join(" ")
    end

    def maintainers_metadata(name)
      json = get_json("https://azuresearch-usnc.nuget.org/query?q=packageid:#{name.downcase}")
      json['data'][0]['owners'].map do |user|
        {
          uuid: user,
          login: user
        }
      end
    rescue StandardError
      []
    end

    def maintainer_url(maintainer)
      "https://www.nuget.org/profiles/#{maintainer.login}"
    end

    def deprecation_info(name)
      releases = get_releases(name)
      return { is_deprecated: false, message: nil } if releases.blank?

      latest_listed = releases.reverse.find { |r| r.dig("catalogEntry", "listed") != false }
      return { is_deprecated: false, message: nil } unless latest_listed

      deprecation = latest_listed.dig("catalogEntry", "deprecation")
      return { is_deprecated: false, message: nil } unless deprecation

      message_parts = []
      message_parts << "Reasons: #{deprecation['reasons'].join(', ')}" if deprecation['reasons'].present?
      message_parts << deprecation['message'] if deprecation['message'].present?
      if deprecation['alternatePackage'].present?
        alt = deprecation['alternatePackage']
        message_parts << "Use #{alt['id']} instead" + (alt['range'].present? ? " (#{alt['range']})" : "")
      end

      {
        is_deprecated: true,
        message: message_parts.any? ? message_parts.join('. ') : nil,
        reasons: deprecation['reasons'],
        alternate_package: deprecation['alternatePackage']
      }
    rescue StandardError
      { is_deprecated: false, message: nil }
    end
  end
end
