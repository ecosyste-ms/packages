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

    def check_status_url(package)
      group_id, artifact_id = *package.name.split(':', 2)
      "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/"
    end

    def download_url(package, version)
      return nil unless version.present?
      group_id, artifact_id = *package.name.split(':', 2)
      
      "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.jar"
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
      get_html("#{@registry_url}/#{namespace.gsub(".", "/")}/").css("a").map do |a|
        next if a.text == "../"
        next if a.text[-1] != "/"
        namespace + ":" + a.text.gsub('/', '')
      end.compact
    end

    def recently_updated_package_names
      if is_maven_central?
        (recently_updated_package_names_from_sonatype + recently_updated_package_names_from_libraries_io).uniq
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

      response = connection.post do |req|
        req.body = {
          size: 20,
          sortField: "publishedDate",
          sortDirection: "desc"
        }.to_json
      end

      json = JSON.parse(response.body)
      json.dig("components")&.map { |c| c["id"].gsub('pkg:maven/', '').gsub('/', ':') } || []
    rescue => e
      Rails.logger.error("Error fetching recently updated from Sonatype: #{e}")
      []
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
      directory_url = "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/"
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
          begin
            license_list = licenses(pom).join(',')
          rescue StandardError
            license_list = nil
          end

          properties = extract_pom_properties(pom)
          published_at_node = pom.locate("publishedAt").first
          {
            number: version,
            published_at: published_at_node ? Time.parse(published_at_node.text) : nil,
            licenses: license_list,
            metadata: {
              properties: properties,
              java_version: extract_java_version(pom),
              maven_compiler_source: properties["maven.compiler.source"],
              maven_compiler_target: properties["maven.compiler.target"],
              maven_compiler_release: properties["maven.compiler.release"],
              repositories: extract_repository_urls(pom),
              distribution_repositories: extract_distribution_repository_urls(pom)
            }
          }
      rescue Ox::Error
        next
        end
        .compact
    end

    def dependencies_metadata(name, version, mapped_package)
      group_id, artifact_id = *name.split(':', 2)
      url = "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.pom"
      pom_file = generate_effective_pom(request(url).body)
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
        repository_url: repo_fallback(
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

    def extract_pom_value(xml, location, parent_properties = {})
      Bibliothecary::Parsers::Maven.extract_pom_info(xml, location, parent_properties) rescue nil
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
      return xml_body unless ENV['ENABLE_MAVEN_EFFECTIVE_POM'] == 'true'

      Tempfile.create(%w[pom_ .xml]) do |input_file|
        File.write(input_file.path, xml_body)
        input_file.flush

        # Run Maven to generate effective POM
        Tempfile.create(%w[effective_pom_ .xml]) do |output_file|
          # Throttle based on concurrent Maven processes
          wait_for_maven_capacity

          begin
            # Build command - use timeout/nice in production (Docker has coreutils)
            # Fallback to plain mvn on dev machines
            if File.exist?("/usr/bin/timeout") || File.exist?("/bin/timeout")
              cmd = ["timeout", "180s", "nice", "-n", "10", "mvn", "help:effective-pom", "-B", "-q", "-f", input_file.path, "-Doutput=#{output_file.path}"]
            else
              cmd = ["mvn", "help:effective-pom", "-B", "-q", "-f", input_file.path, "-Doutput=#{output_file.path}"]
            end

            env = {
              "MAVEN_OPTS" => "-Xmx128m -Xms64m -XX:+UseSerialGC -XX:MaxMetaspaceSize=64m -XX:ActiveProcessorCount=1"
            }

            stdout, stderr, status = Open3.capture3(env, *cmd)

            unless status.success?
              return xml_body
            end

            # Parse the effective POM
            File.read(output_file.path)
          ensure
            release_maven_capacity
          end
        end
      end

    rescue => e
      xml_body
    end

    def wait_for_maven_capacity
      max_concurrent = ENV.fetch('MAX_CONCURRENT_MAVEN', '10').to_i
      redis_key = 'maven:running_processes'
      max_wait = 300

      started_at = Time.now

      lua_script = <<-LUA
        local key = KEYS[1]
        local max = tonumber(ARGV[1])
        local current = tonumber(redis.call('get', key) or 0)
        if current < max then
          redis.call('incr', key)
          redis.call('expire', key, 300)
          return 1
        else
          return 0
        end
      LUA

      loop do
        result = REDIS.eval(lua_script, keys: [redis_key], argv: [max_concurrent])
        break if result == 1

        if Time.now - started_at > max_wait
          Rails.logger.error("Timed out waiting for Maven capacity after #{max_wait}s")
          raise "Maven capacity timeout"
        end

        sleep(0.5)
      end
    rescue => e
      Rails.logger.error("Failed to acquire Maven capacity: #{e.message}")
      raise
    end

    def release_maven_capacity
      redis_key = 'maven:running_processes'
      REDIS.decr(redis_key)
    rescue => e
      Rails.logger.error("Failed to release Maven capacity: #{e.message}")
    end

    def download_pom(group_id, artifact_id, version)
      @pom_cache ||= {}
      cache_key = "#{group_id}/#{artifact_id}/#{version}"
      return @pom_cache[cache_key] if @pom_cache.key?(cache_key)

      @pom_cache[cache_key] = fetch_pom(group_id, artifact_id, version)
    end

    def fetch_pom(group_id, artifact_id, version)
      url = "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.pom"
      pom_request = request(url)
      return nil if pom_request.status == 404
      xml = Ox.parse(generate_effective_pom(pom_request.body))
      return nil if xml.nil?
      published_at = pom_request.headers["Last-Modified"]
      if published_at.present?
        pat = Ox::Element.new("publishedAt")
        pat << published_at
        xml << pat
      end
      xml
    rescue URI::InvalidURIError, Ox::Error
      nil
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

      # Enhanced license detection from comments and URLs
      licenses_from_comments(xml) + licenses_from_urls(xml)
    end

    def licenses_from_comments(xml)
      comments = xml.locate("*/^Comment")
      license_comment_map = {
        "http://www.apache.org/licenses/LICENSE-2.0" => "Apache-2.0",
        "http://www.eclipse.org/legal/epl-v10" => "Eclipse Public License (EPL), Version 1.0",
        "http://www.eclipse.org/legal/epl-2.0" => "Eclipse Public License (EPL), Version 2.0",
        "http://www.eclipse.org/org/documents/edl-v10" => "Eclipse Distribution License (EDL), Version 1.0",
        "Apache License" => "Apache-2.0",
        "MIT License" => "MIT",
        "GPL" => "GPL",
        "BSD" => "BSD"
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
        "http://www.eclipse.org/legal/epl-v10.html" => "Eclipse Public License (EPL), Version 1.0",
        "http://www.eclipse.org/legal/epl-v20.html" => "Eclipse Public License (EPL), Version 2.0"
      }
      
      license_urls.map { |url| url_license_map[url.strip] }.compact
    end

    private

    def is_maven_central?
      @registry_url == "https://repo.maven.apache.org/maven2" || @registry_url == "https://repo1.maven.org/maven2"
    end

    def supports_archetype_catalog?
      case @registry_url
      when "https://repo.maven.apache.org/maven2", "https://repo1.maven.org/maven2"
        true
      when "https://repository.jboss.org/nexus/content/repositories/releases"
        true
      when "https://repository.apache.org/content/repositories/releases"
        true
      when "https://repository.apache.org/content/repositories/snapshots"
        true
      when "https://artifacts.alfresco.com/nexus/content/repositories/public"
        true
      when "https://repository.cloudera.com/content/repositories/public"
        true
      else
        false
      end
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
