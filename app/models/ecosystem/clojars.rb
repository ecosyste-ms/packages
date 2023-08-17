module Ecosystem
  class Clojars < Base

    def download_url(package, version)
      return nil unless version.present?
      group_id, artifact_id = *package.name.split('/', 2)
      artifact_id = group_id if artifact_id.blank?
      
      "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.jar"
    end

    def registry_url(package, version = nil)
      "https://clojars.org/#{package.name}/#{version.present? ? 'versions/' + version.number : ''}"
    end

    def documentation_url(package, version = nil)
      "https://cljdoc.org/d/#{package.name}/#{version}"
    end

    def all_package_names
      poms = get_raw('https://repo.clojars.org/all-poms.txt').split("\n")
      names = poms.map do |pom|
        parts = pom.split('/')[1..-3]
        if parts.length == 3
          "#{parts[0]}.#{parts[1]}/#{parts[2]}"
        else
          if parts[0] == parts[1]
            parts[0]
          else
            parts.join('/')
          end
        end
      end
      names.uniq
    end

    def recently_updated_package_names
      get_html("https://clojars.org/").css(".recent-jar-title a").map(&:text)
    rescue
      []
    end

    def fetch_package_metadata(name)
      group_id, artifact_id = *name.split('/', 2)
      artifact_id = group_id if artifact_id.blank?
      
      url = "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/maven-metadata.xml"
      xml = get_xml(url)
      version_numbers = xml.css("version").map(&:text).filter { |item| !item.ends_with?("-SNAPSHOT") }
      return {} if version_numbers.empty?
      latest_version_xml = fetch_latest_available_pom(group_id, artifact_id, version_numbers)
      return nil if latest_version_xml.nil?
      mapping_from_pom_xml(latest_version_xml, 0).merge({ name: name, versions: version_numbers, downloads: downloads(name), downloads_period: 'total', namespace: group_id })
    rescue
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

    def downloads(name)
      get_json("https://clojars.org/api/artifacts/#{name}").dig("downloads")
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkg_metadata[:versions].reject{|v| existing_version_numbers.include?(v)}.sort.reverse.first(50)
        .map do |version|
          group_id, artifact_id = *pkg_metadata[:name].split('/', 2)
          artifact_id = group_id if artifact_id.blank?
          pom = get_pom(group_id, artifact_id, version)
          next if pom.nil?
          begin
            license_list = licenses(pom).join(",")
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
      group_id, artifact_id = *name.split('/', 2)
      artifact_id = group_id if artifact_id.blank?
      url = "#{@registry_url}/#{group_id.gsub(".", "/")}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.pom"
      pom_file = request(url).body
      Bibliothecary::Parsers::Maven.parse_pom_manifest(pom_file, mapped_package[:properties]).map do |dep|
        name = dep[:name] 
        name = name.split(':').first if name.split(':')[0] == name.split(':')[1]
        {
          package_name: name,
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

    def maintainers_metadata(name)
      user = get_json("https://clojars.org/api/artifacts/#{name}").dig("user")
      return [] unless user.present?
      # TODO support multiple maintainers via groups
      [{
        uuid: user,
        login: user
      }]
    rescue StandardError
      []
    end

    def maintainer_url(maintainer)
      "https://clojars.org/users/#{maintainer.login}"
    end
  end
end
