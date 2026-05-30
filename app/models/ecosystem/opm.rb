# frozen_string_literal: true

module Ecosystem
  class Opm < Base
    def registry_url(package, version = nil)
      url = "#{@registry_url}/package/#{package.name}/"
      url += "?version=#{version}" if version.present?
      url
    end

    def download_url(package, version = nil)
      return nil unless version.present?

      owner, name = package.name.split('/', 2)
      return nil unless owner.present? && name.present?

      "#{@registry_url}/download/#{owner}/#{name}-#{version}.tar.gz"
    end

    def documentation_url(package, _version = nil)
      registry_url(package)
    end

    def install_command(package, version = nil)
      version_part = version ? " #{version}" : ""
      "opm get #{package.name}#{version_part}"
    end

    def check_status(package)
      html = fetch_package_metadata(package.name)
      return nil if html.present?

      "removed"
    end

    def all_package_names
      package_names_from_page(get_html("#{@registry_url}/packages"))
    rescue
      []
    end

    def recently_updated_package_names
      all_package_names.first(100)
    end

    def fetch_package_metadata_uncached(name)
      get_html("#{@registry_url}/package/#{name}/")
    rescue
      nil
    end

    def map_package_metadata(html)
      return false unless html.present?

      title = html.at_css('h2')&.text&.strip
      account = metadata_value(html, 'Account')
      repository_url = html.at_xpath("//h3[normalize-space()='Repo']/following-sibling::a[1]")&.[]('href')
      name = [account, title].compact.join('/')

      {
        name: name,
        description: html.at_css('.description p')&.text&.strip,
        homepage: registry_url(Package.new(name: name)),
        repository_url: repo_fallback(repository_url, nil),
        licenses: license_from_html(html) || 'Unknown',
        versions: html.css('.package_list .package_row .version_name').map { |node| node.text.strip }.reject(&:blank?).uniq,
        metadata: {
          'account' => account,
          'repo' => repository_url,
          'dependencies' => dependencies_from_html(html)
        }
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkg_metadata[:versions]
        .reject { |version| existing_version_numbers.include?(version) }
        .map do |version|
          {
            number: version,
            published_at: nil,
            licenses: pkg_metadata[:licenses],
            metadata: pkg_metadata[:metadata]
          }
        end
    end

    def dependencies_metadata(_name, _version, package)
      Array.wrap(package.metadata&.dig('dependencies')).map do |dependency|
        dep_name, requirements = dependency.split(/\s+/, 2)
        next unless dep_name&.include?('/')

        {
          package_name: dep_name,
          requirements: requirements.presence || '*',
          kind: 'runtime',
          ecosystem: self.class.name.demodulize.downcase,
        }
      end.compact
    end

    private

    def package_names_from_page(html)
      html.css('a.title').map { |link| link.text.strip }.reject(&:blank?).uniq
    end

    def metadata_value(html, heading)
      node = html.at_xpath("//h3[normalize-space()='#{heading}']")
      node&.parent&.text&.sub(heading, '')&.strip
    end

    def dependencies_from_html(html)
      dependency_heading = html.at_xpath("//h3[normalize-space()='Dependencies']")
      dependency_heading&.next_element&.text&.split(',')&.map(&:strip)&.reject(&:blank?) || []
    end

    def license_from_html(html)
      license_heading = html.at_xpath("//*[self::h1 or self::h2 or self::h3][contains(translate(normalize-space(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'license')]")
      license_text = license_heading&.next_element&.text&.strip
      return nil if license_text.blank?

      license_text.lines.first.strip
    end
  end
end
