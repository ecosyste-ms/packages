module Ecosystem
  class Maven < Base

    def purl(package, version = nil)
      group_id, artifact_id = *package.name.split(':', 2)
      PackageURL.new(
        type: purl_type,
        namespace: group_id,
        name: artifact_id,
        version: version.try(:number).try(:encode,'iso-8859-1')
      ).to_s
    end

    def self.namespace_seperator
      ':'
    end

    def download_url(package, version)
      return nil unless version.present?
      group_id, artifact_id = *package.name.split(':', 2)
      
      "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.jar"
    end

    def registry_url(package, version = nil)
      group_id, artifact_id = *package.name.split(':', 2)

      if @registry_url == "https://repo.maven.apache.org/maven2" || @registry_url == "https://repo1.maven.org/maven2"
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
      get_xml("#{@registry_url}/archetype-catalog.xml").css("archetype").map do |archetype|
        archetype.css('groupId').first.text + ":" + archetype.css('artifactId').first.text
      end.uniq
    end

    def namespace_package_names(namespace)
      get_html("#{@registry_url}/#{namespace.gsub(".", "/")}/").css("a").map do |a|
        next if a.text == "../"
        next if a.text[-1] != "/"
        namespace + ":" + a.text.gsub('/', '')
      end.compact
    end

    def recently_updated_package_names
      (recently_updated_package_names_from_sonatype + recently_updated_package_names_from_libraries_io).uniq
    end

    def recently_updated_package_names_from_sonatype
      url = "https://central.sonatype.com/api/internal/browse/components?repository=maven-central"
      connection = Faraday.new(url, headers: { "User-Agent" => "packages.ecosyste.ms (packages@ecosyste.ms)", "Content-Type" => "application/json" }) do |builder|
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
      get_json("https://maven.libraries.io/mavenCentral/recent").sort_by{|h| Time.at(h['lastModified']/1000)}.reverse.map{|h| h["name"]}.uniq.first(20) rescue []
    end

    def fetch_package_metadata(name)
      group_id, artifact_id = *name.split(':', 2)
      
      url = "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/maven-metadata.xml"
      xml = get_xml(url)
      version_numbers = xml.css("version").map(&:text).filter { |item| !item.ends_with?("-SNAPSHOT") }
      return {} if version_numbers.empty?
      latest_version_xml = fetch_latest_available_pom(group_id, artifact_id, version_numbers)
      return nil if latest_version_xml.nil?
      mapping_from_pom_xml(latest_version_xml, 0).merge({ name: name, versions: version_numbers, namespace: group_id })
    rescue => e
      p e
      nil
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
      pkg_metadata[:versions].reject{|v| existing_version_numbers.include?(v)}.sort.reverse.first(50)
        .map do |version|
          pom = get_pom(*pkg_metadata[:name].split(':', 2), version)
          next if pom.nil?
          begin
            license_list = licenses(pom).join(',')
          rescue StandardError
            license_list = nil
          end
          
          {
            number: version,
            published_at: Time.parse(pom.locate("publishedAt").first.text),
            licenses: license_list,
          }
      rescue Ox::Error
        next
        end
        .compact
    end

    def dependencies_metadata(name, version, mapped_package)
      group_id, artifact_id = *name.split(':', 2)
      url = "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.pom"
      pom_file = request(url).body
      Bibliothecary::Parsers::Maven.parse_pom_manifest(pom_file, mapped_package[:properties]).map do |dep|
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
      }.select { |_k, v| v.present? }

      parent.merge(child)
    end

    def extract_pom_value(xml, location, parent_properties = {})
      Bibliothecary::Parsers::Maven.extract_pom_info(xml, location, parent_properties) rescue nil
    end

    def extract_pom_properties(xml)
      xml.locate("properties/*").each_with_object({}) do |prop_node, all|
        all[prop_node.value] = prop_node.nodes.first if prop_node.respond_to?(:nodes)
      end
    end

    def download_pom(group_id, artifact_id, version)
      url = "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.pom"
      pom_request = request(url)
      return nil if pom_request.status == 404
      xml = Ox.parse(pom_request.body)
      return nil if xml.nil?
      published_at = pom_request.headers["Last-Modified"]
      pat = Ox::Element.new("publishedAt")
      pat << published_at
      xml << pat
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

      comments = xml.locate("*/^Comment")
      {
        "http://www.apache.org/licenses/LICENSE-2.0" => "Apache-2.0",
        "http://www.eclipse.org/legal/epl-v10" => "Eclipse Public License (EPL), Version 1.0",
        "http://www.eclipse.org/legal/epl-2.0" => "Eclipse Public License (EPL), Version 2.0",
        "http://www.eclipse.org/org/documents/edl-v10" => "Eclipse Distribution License (EDL), Version 1.0",
      }.select { |string, _| comments.any? { |c| c.value.include?(string) } }
        .map(&:last)
    end
  end
end
