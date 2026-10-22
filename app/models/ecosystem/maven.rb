module Ecosystem
  class Maven < Base

    def purl_params(package, version = nil)
      group_id, artifact_id = *package.name.split(':', 2)
      {
        type: purl_type,
        namespace: group_id,
        name: artifact_id,
        version: version.try(:number).try(:encode,'iso-8859-1')
      }
    end

    def self.namespace_separator
      ':'
    end

    # Nexus 3 answers 200 for any directory path, so check a file that only exists for real artifacts.
    def check_status_url(package)
      group_id, artifact_id = *package.name.split(':', 2)
      "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/maven-metadata.xml"
    end

    # Maven artifact handlers map packaging to the published file extension.
    # Packaging types not listed here (jar, bundle, maven-plugin, ejb, ...) publish a JAR.
    PACKAGING_EXTENSIONS = {
      "pom" => "pom",
      "aar" => "aar",
      "war" => "war",
      "ear" => "ear",
      "rar" => "rar",
    }.freeze

    def download_url(package, version)
      return nil unless version.present?
      group_id, artifact_id = *package.name.split(':', 2)
      packaging = version.respond_to?(:metadata) ? version.metadata&.dig("packaging") : nil

      "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.#{artifact_extension(packaging)}"
    end

    def artifact_extension(packaging)
      PACKAGING_EXTENSIONS.fetch(packaging.to_s.strip.downcase.presence || "jar", "jar")
    end

    def registry_url(package, version = nil)
      group_id, artifact_id = *package.name.split(':', 2)

      if is_maven_central?
        "https://central.sonatype.com/artifact/#{group_id}/#{artifact_id}/#{version}"
      else
        "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/#{version.present? ? version.number + '/' : ''}"
      end
    end

    def documentation_url(package, version = nil)
      group_id, artifact_id = *package.name.split(':', 2)
      "https://appdoc.app/artifact/#{group_id}/#{artifact_id}/#{version}"
    end

    def all_package_names
      if supports_archetype_catalog?
        get_xml("#{@registry_url}/archetype-catalog.xml").css("archetype").map do |archetype|
          archetype.css('groupId').first.text + ":" + archetype.css('artifactId').first.text
        end.uniq
      else
        []
      end
    rescue => e
      Rails.logger.error("Error fetching all package names: #{e}")
      []
    end

    def namespace_package_names(namespace)
      get_html(listing_url(namespace.gsub(".", "/"))).css("a").map do |a|
        next if a.text == "../"
        next if a.text[-1] != "/"
        namespace + ":" + a.text.gsub('/', '')
      end.compact
    end

    # Multi-module releases publish many artifacts at once and the recent feed
    # only catches some, so list the namespace to queue the siblings we lack.
    def sync_subpackages_async(package)
      namespace = package.namespace
      return if namespace.blank? || !is_maven_central?
      return unless Rails.cache.write("maven_namespace_listing/#{@registry.id}/#{namespace}", true, expires_in: 1.day, unless_exist: true)

      names = namespace_package_names(namespace)
      names -= @registry.packages.where(name: names).pluck(:name)
      # Listings mix sub-groups in with artifacts; skip children we already know as namespaces.
      sub_groups = @registry.packages.where(namespace: names.map { |name| name.sub(':', '.') }).distinct.pluck(:namespace).to_set
      names = names.reject { |name| sub_groups.include?(name.sub(':', '.')) }
      @registry.sync_packages_async(names)
    rescue => e
      Rails.logger.error("Error syncing namespace siblings for #{package.name}: #{e.class} #{e.message}")
    end

    def recently_updated_package_names
      if is_maven_central?
        # maven.libraries.io/mavenCentral/recent stopped updating on 2026-09-24
        # (recently_updated_package_names_from_sonatype + recently_updated_package_names_from_libraries_io).uniq
        recently_updated_package_names_from_sonatype.uniq
      elsif supports_archetype_catalog?
        recently_updated_package_names_from_archetype_catalog
      else
        []
      end
    end

    def recently_updated_package_names_from_sonatype
      return [] unless is_maven_central?
      
      url = "https://central.sonatype.com/api/internal/browse/components?repository=maven-central"
      connection = Faraday.new(url, headers: { "User-Agent" => "packages.ecosyste.ms", "Content-Type" => "application/json" }) do |builder|
        builder.use Faraday::FollowRedirects::Middleware
        builder.request :retry, { max: 5, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2 }
        builder.request :instrumentation
        builder.adapter Faraday.default_adapter, accept_encoding: "gzip"
      end

      names = []
      # The API caps size at 20, so page to see more than one release burst.
      SONATYPE_RECENT_PAGES.times do |page|
        response = connection.post do |req|
          req.body = {
            size: 20,
            page: page,
            sortField: "publishedDate",
            sortDirection: "desc"
          }.to_json
        end

        components = JSON.parse(response.body)["components"]
        break if components.blank?
        names.concat(components.map { |c| c["id"].gsub('pkg:maven/', '').gsub('/', ':') })
      end
      names
    rescue => e
      Rails.logger.error("Error fetching recently updated from Sonatype: #{e}")
      Array(names)
    end

    def recently_updated_package_names_from_libraries_io
      return [] unless is_maven_central?
      
      get_json("https://maven.libraries.io/mavenCentral/recent").sort_by{|h| Time.at(h['lastModified']/1000)}.reverse.map{|h| h["name"]}.uniq.first(20) rescue []
    end

    def recently_updated_package_names_from_archetype_catalog
      return [] unless supports_archetype_catalog?
      
      # Get all packages from archetype catalog
      catalog_packages = get_xml("#{@registry_url}/archetype-catalog.xml").css("archetype").map do |archetype|
        group_id = archetype.css('groupId').first&.text
        artifact_id = archetype.css('artifactId').first&.text
        version = archetype.css('version').first&.text
        
        next if group_id.blank? || artifact_id.blank? || version.blank?
        
        {
          name: "#{group_id}:#{artifact_id}",
          version: version
        }
      end.compact
      
      # Find packages/versions we don't have in the database
      missing_packages = find_missing_packages_and_versions(catalog_packages)
      
      # Return package names of missing items (limit to avoid overwhelming)
      missing_packages.map { |pkg| pkg[:name] }.uniq.first(50)
    rescue => e
      Rails.logger.error("Error fetching recent packages from archetype catalog: #{e}")
      []
    end

    def fetch_package_metadata_uncached(name)
      group_id, artifact_id = *name.split(':', 2)

      url = "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/maven-metadata.xml"
      Rails.logger.info "Fetching Maven metadata for #{name} from #{url}"
      xml = get_xml(url)

      # For snapshot repositories, include SNAPSHOT versions; for others, exclude them
      if is_snapshot_repository?
        version_numbers = xml.css("version").map(&:text).filter { |v| valid_version?(v) }
      else
        version_numbers = xml.css("version").map(&:text).filter { |item| !item.ends_with?("-SNAPSHOT") && valid_version?(item) }
      end

      if version_numbers.empty?
        Rails.logger.info "No valid versions found for #{name} in maven-metadata.xml, trying HTML directory listing fallback"
        version_numbers = fetch_versions_from_html_directory(group_id, artifact_id)

        if version_numbers.empty?
          Rails.logger.error "No valid versions found for #{name} from either maven-metadata.xml or HTML directory listing"
          return {}
        end
        Rails.logger.info "Found #{version_numbers.size} versions from HTML directory listing for #{name}"
      end
      latest_version_xml = fetch_latest_available_pom(group_id, artifact_id, version_numbers)
      if latest_version_xml.nil?
        Rails.logger.error "Failed to fetch latest POM for #{name}, tried versions: #{version_numbers.last(5).join(', ')}"
        return nil
      end
      mapping_from_pom_xml(latest_version_xml, 0).merge({ name: name, versions: version_numbers, namespace: group_id })
    rescue Faraday::Error => e
      # Fallback: Try to parse HTML directory listing for packages without maven-metadata.xml
      # This handles legacy packages published before maven-metadata.xml was standardized
      if e.response && [404].include?(e.response[:status])
        Rails.logger.info "maven-metadata.xml not found for #{name}, trying HTML directory listing fallback"
        version_numbers = fetch_versions_from_html_directory(group_id, artifact_id)

        if version_numbers.any?
          Rails.logger.info "Found #{version_numbers.size} versions from HTML directory listing for #{name}"
          latest_version_xml = fetch_latest_available_pom(group_id, artifact_id, version_numbers)
          if latest_version_xml.nil?
            Rails.logger.error "Failed to fetch latest POM for #{name} via HTML fallback, tried versions: #{version_numbers.last(5).join(', ')}"
            return nil
          end
          return mapping_from_pom_xml(latest_version_xml, 0).merge({ name: name, versions: version_numbers, namespace: group_id })
        end
      end

      Rails.logger.error "HTTP error fetching package metadata for #{name}: #{e.class} - #{e.message}"
      Rails.logger.error "Response status: #{e.response[:status]}" if e.response
      Rails.logger.error "URL attempted: #{url}"
      nil
    rescue => e
      Rails.logger.error "Error fetching package metadata for #{name}: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      nil
    end

    def fetch_versions_from_html_directory(group_id, artifact_id)
      directory_url = directory_listing_url(group_id, artifact_id)
      Rails.logger.info "Fetching versions from HTML directory: #{directory_url}"
      html = get_html(directory_url)

      version_numbers = html.css("a").map do |a|
        next if a.text == "../"
        next unless a.text.end_with?("/")

        version = a.text.gsub('/', '')
        next unless valid_version?(version)
        next if !is_snapshot_repository? && version.ends_with?("-SNAPSHOT")

        version
      end.compact

      version_numbers
    rescue => e
      Rails.logger.error "Failed to fetch versions from HTML directory for #{group_id}:#{artifact_id}: #{e.message}"
      []
    end

    def fetch_latest_available_pom(group_id, artifact_id, version_numbers)
      pom = nil
      numbers = version_numbers.dup
      while pom.nil? && numbers.any?
        version_number = numbers.pop
        pom = download_pom(group_id, artifact_id, version_number)
      end
      pom
    end

    def map_package_metadata(package)
      return false if package.blank?
      package
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkg_metadata[:versions].reject{|v| existing_version_numbers.include?(v)}.sort_by { |v| Gem::Version.new(v) rescue Gem::Version.new('0') }.reverse
        .map do |version|
          pom = get_pom(*pkg_metadata[:name].split(':', 2), version)
          next if pom.nil?
          # Packaging and relocation describe the artifact published at these
          # coordinates, so read them from the original POM (get_pom follows relocations).
          original_pom = download_pom(*pkg_metadata[:name].split(':', 2), version)
          packaging = extract_packaging(original_pom)
          relocation = extract_relocation(original_pom, pkg_metadata[:name], version)
          begin
            license_list = licenses(pom).join(',')
          rescue StandardError
            license_list = nil
          end

          properties = extract_pom_properties(pom)
          published_at_node = pom.locate("publishedAt").first
          if published_at_node.nil? && @registry_url == MAVEN_CENTRAL_GCS_MIRROR && @registry.id
            MavenCentralPublishedAtWorker.perform_in(5.minutes, @registry.id, pkg_metadata[:name], version)
          end
          {
            number: version,
            published_at: published_at_node ? Time.parse(published_at_node.text) : nil,
            licenses: license_list,
            integrity: version_integrity(pkg_metadata[:name], version, packaging),
            metadata: {
              properties: properties,
              java_version: extract_java_version(pom),
              maven_compiler_source: properties["maven.compiler.source"],
              maven_compiler_target: properties["maven.compiler.target"],
              maven_compiler_release: properties["maven.compiler.release"],
              repositories: extract_repository_urls(pom),
              distribution_repositories: extract_distribution_repository_urls(pom),
              packaging: packaging,
              relocation: relocation
            }
          }
      rescue Ox::Error
        next
        end
        .compact
    end

    def version_integrity(name, version, packaging = nil)
      group_id, artifact_id = *name.split(':', 2)
      url = "#{@registry_url}/#{group_id.gsub('.', '/')}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.#{artifact_extension(packaging)}.sha1"
      resp = request(url)
      return nil unless resp.respond_to?(:success?) && resp.success?
      sha1 = resp.body.to_s.strip[/\A[0-9a-fA-F]{40}/]
      sha1 ? "sha1-#{sha1.downcase}" : nil
    rescue Faraday::Error
      nil
    end

    def dependencies_metadata(name, version, mapped_package)
      group_id, artifact_id = *name.split(':', 2)
      effective = fetch_effective_pom(group_id, artifact_id, version)
      return [] if effective.nil?
      pom_file = effective[:body]
      properties = mapped_package&.dig(:properties) || {}
      Bibliothecary::Parsers::Maven.parse_pom_manifest(pom_file, properties).map do |dep|
        {
          package_name: dep[:name],
          requirements: dep[:requirement],
          kind: dep[:type],
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end

    def mapping_from_pom_xml(version_xml, depth = 0)
      return nil if version_xml.nil?
      xml = if version_xml.respond_to?("project")
              version_xml.project
            else
              version_xml
            end

      parent = {
        description: nil,
        homepage: nil,
        repository_url: "",
        licenses: "",
        properties: {},
      }
      if xml.locate("parent").present? && depth < 5
        group_id = extract_pom_value(xml, "parent/groupId")&.strip
        artifact_id = extract_pom_value(xml, "parent/artifactId")&.strip
        version = extract_pom_value(xml, "parent/version")&.strip
        if group_id && artifact_id && version
          par = mapping_from_pom_xml(
            get_pom(group_id, artifact_id, version),
            depth + 1
          )
          parent = par unless par.nil?
        end
      end

      # merge with parent data if available and take child values on overlap
      child = {
        description: extract_pom_value(xml, "description", parent[:properties]),
        homepage: extract_pom_value(xml, "url", parent[:properties])&.strip,
        repository_url: scm_repository_url(
          extract_pom_value(xml, "scm/connection", parent[:properties])&.strip,
          extract_pom_value(xml, "scm/url", parent[:properties])&.strip,
          extract_pom_value(xml, "url", parent[:properties])&.strip
        ),
        licenses: licenses(version_xml).join(","),
        properties: parent[:properties].merge(extract_pom_properties(xml)),
        metadata: {
          repositories: extract_repository_urls(xml),
          distribution_repositories: extract_distribution_repository_urls(xml)
        }.select { |_k, v| v.present? && v.any? }
      }.select { |_k, v| v.present? }

      parent.merge(child)
    end

    APACHE_GIT_HOSTS = %w[git-wip-us.apache.org git.apache.org gitbox.apache.org].freeze

    # Prefer the Git clone URL in scm/connection, then scm/url, then the homepage.
    def scm_repository_url(connection, scm_url, homepage)
      [scm_connection_clone_url(connection), scm_url].each do |candidate|
        found = apache_git_repository_url(candidate) || (UrlParser.try_all(candidate) rescue nil)
        return found if found.present?
      end
      repo_fallback(scm_url, homepage)
    end

    # "scm:git:https://host/org/repo.git/module" -> "https://host/org/repo.git"
    def scm_connection_clone_url(connection)
      return nil if connection.blank?
      return nil if connection.match?(/\Ascm[:|]/i) && !connection.match?(/\Ascm[:|]git[:|]/i)
      url = connection.sub(/\Ascm[:|]git[:|]/i, "")
      url.sub(%r{(\.git)/.*\z}i, '\1')
    end

    # Apache Git locations moved to GitBox. Handles /repos/asf/<name>.git paths
    # and Gitweb query URLs (/repos/asf?p=<name>.git;a=summary), keeping the repository root.
    def apache_git_repository_url(url)
      return nil if url.blank?
      uri = URI.parse(url)
      return nil unless APACHE_GIT_HOSTS.include?(uri.host)
      name = if uri.query
        Rack::Utils.parse_query(uri.query.tr(";", "&"))["p"].to_s[%r{\A([^/]+\.git)}i, 1]
      else
        uri.path.to_s[%r{\A/(?:repos/asf/)?([^/]+\.git)}i, 1]
      end
      name.present? ? "https://gitbox.apache.org/repos/asf/#{name}" : nil
    rescue URI::InvalidURIError
      nil
    end

    def extract_pom_value(xml, location, parent_properties = {})
      Bibliothecary::Parsers::Maven.extract_pom_info(xml, location, parent_properties) rescue nil
    end

    def extract_packaging(pom)
      return nil if pom.nil?
      packaging = pom.locate("packaging/?[0]").first
      packaging.to_s.strip.presence || "jar"
    end

    def extract_relocation(pom, name, version)
      return nil if pom.nil?
      return nil if pom.locate("distributionManagement/relocation").first.nil?
      group_id, artifact_id = *name.split(':', 2)
      {
        "groupId" => pom.locate("distributionManagement/relocation/groupId/?[0]").first&.to_s || group_id,
        "artifactId" => pom.locate("distributionManagement/relocation/artifactId/?[0]").first&.to_s || artifact_id,
        "version" => pom.locate("distributionManagement/relocation/version/?[0]").first&.to_s || version,
      }
    end

    def extract_pom_properties(xml)
      xml.locate("*/properties").flat_map(&:nodes).each_with_object({}) do |prop_node, all|
        if prop_node.respond_to?(:name) && prop_node.respond_to?(:text)
          all[prop_node.name] = prop_node.text
        end
      end
    end

    def extract_java_version(xml)
      properties = extract_pom_properties(xml)
      
      # Look for java.version in properties first
      java_version = properties["java.version"]
      return java_version if java_version.present?
      
      # Look for javaVersion property (used by some Maven plugins)
      java_version_alt = properties["javaVersion"]
      return java_version_alt if java_version_alt.present?
      
      # Fallback to maven.compiler.release, but resolve variables if needed
      release_version = properties["maven.compiler.release"]
      if release_version.present? && release_version == "${java.version}"
        return properties["java.version"]
      elsif release_version.present?
        return release_version
      end
      
      # Fallback to maven.compiler.target
      target_version = properties["maven.compiler.target"]
      return target_version if target_version.present?
      
      nil
    end

    def extract_repository_urls(xml)
      repositories = []
      
      # Extract from <repositories><repository><url>
      xml.locate("*/repositories/repository/url").each do |url_node|
        url = url_node.text&.strip
        repositories << url if url.present? && url.start_with?('http')
      end
      
      repositories.uniq
    end

    def extract_distribution_repository_urls(xml)
      repositories = []
      
      # Extract from <distributionManagement><repository><url>
      xml.locate("*/distributionManagement/repository/url").each do |url_node|
        url = url_node.text&.strip
        repositories << url if url.present? && url.start_with?('http')
      end
      
      # Extract from <distributionManagement><snapshotRepository><url>
      xml.locate("*/distributionManagement/snapshotRepository/url").each do |url_node|
        url = url_node.text&.strip
        repositories << url if url.present? && url.start_with?('http')
      end
      
      repositories.uniq
    end

    def find_missing_packages_and_versions(catalog_packages)
      missing = []
      registry_id = Registry.find_by(url: @registry_url)&.id
      return catalog_packages unless registry_id # If registry not found, consider everything missing
      
      catalog_packages.each do |catalog_pkg|
        # Check if package exists in this registry
        package = Package.joins(:registries).where(
          name: catalog_pkg[:name], 
          ecosystem: 'maven',
          'registries.id': registry_id
        ).first
        
        if package.nil?
          # Package doesn't exist at all
          missing << catalog_pkg
        else
          # Package exists, check if this version exists
          version_exists = package.versions.where(number: catalog_pkg[:version]).exists?
          unless version_exists
            missing << catalog_pkg
          end
        end
      end
      
      missing
    end

    def generate_effective_pom(xml_body)
      capacity_acquired = false
      return xml_body unless ENV['ENABLE_MAVEN_EFFECTIVE_POM'] == 'true'

      capacity_acquired = wait_for_pom_capacity
      return xml_body unless capacity_acquired

      stdout, stderr, status = Open3.capture3(
        "pom", "-f", "-", "-xml", "-repo", @registry_url, "-timeout", "30s",
        stdin_data: xml_body
      )

      unless status.success?
        Rails.logger.warn("pom: effective-pom failed: #{stderr.strip}")
        return xml_body
      end

      stdout
    rescue => e
      Rails.logger.warn("pom: #{e.class}: #{e.message}")
      xml_body
    ensure
      release_pom_capacity if capacity_acquired
    end

    def wait_for_pom_capacity
      max_concurrent = [ENV.fetch('MAX_CONCURRENT_POM', '5').to_i, 1].max
      wait_timeout = [ENV.fetch('POM_CAPACITY_WAIT_TIMEOUT', '5').to_f, 0].max
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait_timeout
      redis_key = 'pom:running_processes'
      lua_script = <<~LUA
        local key = KEYS[1]
        local max = tonumber(ARGV[1])
        local current = tonumber(redis.call('get', key) or 0)
        if current < max then
          redis.call('incr', key)
          redis.call('expire', key, ARGV[2])
          return 1
        end
        return 0
      LUA

      loop do
        result = REDIS.eval(lua_script, keys: [redis_key], argv: [max_concurrent, 60])
        return true if result == 1

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          Rails.logger.warn("pom: capacity limit reached after #{wait_timeout}s")
          return false
        end

        sleep(0.1)
      end
    rescue => e
      Rails.logger.warn("pom: failed to acquire capacity: #{e.message}")
      false
    end

    def release_pom_capacity
      redis_key = 'pom:running_processes'
      lua_script = <<~LUA
        local key = KEYS[1]
        local current = tonumber(redis.call('get', key) or 0)
        if current <= 1 then
          redis.call('del', key)
          return 0
        end
        return redis.call('decr', key)
      LUA
      REDIS.eval(lua_script, keys: [redis_key])
    rescue => e
      Rails.logger.warn("pom: failed to release capacity: #{e.message}")
    end

    def download_pom(group_id, artifact_id, version)
      @pom_cache ||= {}
      cache_key = "#{group_id}/#{artifact_id}/#{version}"
      return @pom_cache[cache_key] if @pom_cache.key?(cache_key)

      @pom_cache[cache_key] = fetch_pom(group_id, artifact_id, version)
    end

    def fetch_pom(group_id, artifact_id, version)
      effective = fetch_effective_pom(group_id, artifact_id, version)
      return nil if effective.nil?
      xml = Ox.parse(effective[:body])
      return nil if xml.nil?
      published_at = effective[:last_modified]
      if published_at.present?
        pat = Ox::Element.new("publishedAt")
        pat << published_at
        xml << pat
      end
      xml
    rescue URI::InvalidURIError, Ox::Error
      nil
    end

    def fetch_effective_pom(group_id, artifact_id, version)
      @effective_pom_cache ||= {}
      key = "#{group_id}/#{artifact_id}/#{version}"
      return @effective_pom_cache[key] if @effective_pom_cache.key?(key)
      url = "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.pom"
      resp = request(url)
      return @effective_pom_cache[key] = nil if resp.status == 404
      @effective_pom_cache[key] = { body: generate_effective_pom(resp.body), last_modified: pom_last_modified(resp.headers) }
    rescue URI::InvalidURIError
      @effective_pom_cache[key] = nil
    end

    def get_pom(group_id, artifact_id, version, seen = [])
      xml = download_pom(group_id, artifact_id, version)
      return nil if xml.nil?
      seen << [group_id, artifact_id, version]

      next_group_id = xml.locate("distributionManagement/relocation/groupId/?[0]").first || group_id
      next_artifact_id = xml.locate("distributionManagement/relocation/artifactId/?[0]").first || artifact_id
      next_version = xml.locate("distributionManagement/relocation/version/?[0]").first || version

      if seen.include?([next_group_id, next_artifact_id, next_version])
        xml

      else
        begin
          get_pom(next_group_id, next_artifact_id, next_version, seen)
        rescue Faraday::Error, Ox::Error
          xml
        end
      end
    end

    def licenses(xml)
      xml_licenses = xml
        .locate("*/licenses/license/name")
        .flat_map(&:nodes).map{|s| s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '') }
      return xml_licenses if xml_licenses.any?

      spdx_expression = licenses_from_spdx_identifier(xml)
      return spdx_expression if spdx_expression.any?

      licenses_from_comments(xml) + licenses_from_urls(xml)
    end

    def licenses_from_spdx_identifier(xml)
      xml.locate("*/^Comment").flat_map do |c|
        c.value.scan(/SPDX-License-Identifier:\s*(.+?)\s*$/).flatten
      end.reject(&:blank?)
    end

    def licenses_from_comments(xml)
      comments = xml.locate("*/^Comment")
      license_comment_map = {
        "http://www.apache.org/licenses/LICENSE-2.0" => "Apache-2.0",
        "http://www.eclipse.org/legal/epl-v10" => "EPL-1.0",
        "http://www.eclipse.org/legal/epl-2.0" => "EPL-2.0",
        "http://www.eclipse.org/org/documents/edl-v10" => "BSD-3-Clause",
        "Apache License" => "Apache-2.0",
        "MIT License" => "MIT",
      }

      license_comment_map.select { |string, _|
        comments.any? { |c| c.value.include?(string) }
      }.map(&:last)
    end

    def licenses_from_urls(xml)
      license_urls = xml.locate("*/licenses/license/url").flat_map(&:nodes).map(&:text)
      url_license_map = {
        "http://www.apache.org/licenses/LICENSE-2.0" => "Apache-2.0",
        "https://www.apache.org/licenses/LICENSE-2.0" => "Apache-2.0",
        "http://opensource.org/licenses/MIT" => "MIT",
        "https://opensource.org/licenses/MIT" => "MIT",
        "http://www.eclipse.org/legal/epl-v10.html" => "EPL-1.0",
        "http://www.eclipse.org/legal/epl-v20.html" => "EPL-2.0"
      }

      license_urls.map { |url| url_license_map[url.strip] }.compact
    end

    MAVEN_CENTRAL_URLS = [
      "https://repo.maven.apache.org/maven2",
      "https://repo1.maven.org/maven2",
      "https://maven-central.storage-download.googleapis.com/maven2"
    ].freeze

    MAVEN_CENTRAL_GCS_MIRROR = "https://maven-central.storage-download.googleapis.com/maven2"

    MAVEN_CENTRAL_ORIGIN = "https://repo1.maven.org/maven2"

    SONATYPE_RECENT_PAGES = 5

    def directory_listing_url(group_id, artifact_id)
      listing_url("#{group_id.gsub(".", "/")}/#{artifact_id}")
    end

    # The Google mirror 404s on bare directory paths and only serves index.html.
    def listing_url(path)
      base = "#{@registry_url}/#{path}/"
      @registry_url == MAVEN_CENTRAL_GCS_MIRROR ? "#{base}index.html" : base
    end

    # The Google mirror's Last-Modified is when the file reached the bucket. The upload time is in
    # x-goog-meta-last-modified, which files from its 2019 bulk import lack; those are dated later
    # from Central by MavenCentralPublishedAtWorker.
    def pom_last_modified(headers)
      return headers["Last-Modified"] unless @registry_url == MAVEN_CENTRAL_GCS_MIRROR

      headers["x-goog-meta-last-modified"]&.delete('"').presence
    end

    def central_published_at(name, version)
      group_id, artifact_id = *name.split(':', 2)
      url = "#{MAVEN_CENTRAL_ORIGIN}/#{group_id.gsub('.', '/')}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.pom"
      connection = Faraday.new do |builder|
        builder.use Faraday::FollowRedirects::Middleware
        builder.request :instrumentation
        builder.response :raise_error, allowed_statuses: [404, 410]
        builder.adapter Faraday.default_adapter
        builder.options.timeout = 10
        builder.options.open_timeout = 5
      end
      response = connection.head(url) { |req| req.headers["User-Agent"] = "packages.ecosyste.ms" }
      last_modified = response.headers["Last-Modified"] if response.success?
      last_modified.present? ? Time.parse(last_modified) : nil
    rescue ArgumentError
      nil
    end

    def self.declared_repositories_key
      'repositories'
    end

    # Drops ${...} placeholders and names without a groupId.
    def self.resolvable_dependency_name?(name)
      name.count(':') == 1 && !name.include?('$')
    end

    private

    def is_maven_central?
      MAVEN_CENTRAL_URLS.include?(@registry_url)
    end

    def supports_archetype_catalog?
      is_maven_central? || @registry.metadata.to_h['archetype_catalog'].present?
    end

    def is_snapshot_repository?
      @registry_url.include?('/snapshots') || @registry_url.include?('-snapshot')
    end

    def valid_version?(version)
      return false unless version.is_a?(String) && version.present?
      
      # Filter out interpolation strings like ${project.version}
      return false if version.include?('${')
      
      # Filter out obviously invalid versions
      return false if version.strip.empty?
      return false if version == 'LATEST' || version == 'RELEASE'
      
      true
    end

  end
end
