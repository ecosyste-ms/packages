# frozen_string_literal: true

module Ecosystem
  class Easybuild < Base
    def self.purl_type
      'easybuild'
    end

    def registry_url(package, _version = nil)
      base = @registry_url.presence || 'https://docs.easybuild.io'
      "#{base}/version-specific/supported-software/#{letter_path(package.name)}/#{package.name}/"
    end

    def install_command(package, version = nil)
      v = version.respond_to?(:number) ? version.number : version
      if v.present?
        "eb #{package.name}-#{v}.eb --robot"
      else
        "eb #{package.name} --robot"
      end
    end

    def download_url(package, version = nil)
      v = version.respond_to?(:number) ? version.number : version
      return nil if v.blank?

      "https://raw.githubusercontent.com/easybuilders/easybuild-easyconfigs/develop/easybuild/easyconfigs/#{letter_path(package.name)}/#{package.name}/#{package.name}-#{v}.eb"
    end

    def check_status_url(package)
      registry_url(package)
    end

    def check_status(package)
      pkg = fetch_package_metadata(package.name)
      return nil if pkg.present? && pkg.is_a?(Hash) && (pkg[:name].present? || pkg['name'].present?)

      url = check_status_url(package)
      response = Faraday.head(url)
      return 'removed' if [400, 404, 410].include?(response.status)
    rescue StandardError => e
      Rails.logger.error "Easybuild#check_status failed: #{e.message}"
      nil
    end

    def all_package_names
      base = @registry_url.presence || 'https://docs.easybuild.io'
      doc = get_html("#{base}/version-specific/supported-software/")
      return [] if doc.nil?

      doc.css('article li a, article a').map do |a|
        href = a['href'].to_s
        if href =~ %r{\A[0-9a-zA-Z]/([^/]+)/?\z}
          a.text.strip
        end
      end.compact.uniq
    rescue StandardError => e
      Rails.logger.error "Easybuild#all_package_names failed: #{e.message}"
      []
    end

    def recently_updated_package_names
      u = 'https://github.com/easybuilders/easybuild-easyconfigs/commits/develop.atom'
      xml = Nokogiri::XML(get_raw(u))
      xml.css('entry title').map do |title_node|
        t = title_node.text.strip
        if t =~ /(?:adding easyconfigs:|new_pr_)([A-Za-z0-9_-]+)/i
          $1
        elsif t =~ /([A-Za-z0-9_-]+)-[0-9]+\.[0-9]+/
          $1
        end
      end.compact.uniq
    rescue StandardError => e
      Rails.logger.error "Easybuild#recently_updated_package_names failed: #{e.message}"
      []
    end

    def fetch_package_metadata_uncached(name)
      base = @registry_url.presence || 'https://docs.easybuild.io'
      url = "#{base}/version-specific/supported-software/#{letter_path(name)}/#{name}/"
      doc = get_html(url)
      return nil if doc.nil?

      h1 = doc.at_css('article h1')
      return nil if h1.nil?

      pkg_name = h1.text.sub(/¶.*/, '').strip.presence || name

      article = doc.at_css('article')
      p_tags = article ? article.css('p') : []
      desc = p_tags.first&.text&.strip

      homepage = nil
      p_tags.each do |p|
        if p.text =~ /homepage\s*:\s*(https?:\/\/[^\s]+)/i
          homepage = $1.strip
        end
      end

      versions = []
      doc.css('table tbody tr').each do |tr|
        cols = tr.css('td').map { |td| td.text.strip }
        next if cols.empty?

        v_num = cols[0]
        tc = cols[1] || ''
        versions << {
          version: v_num,
          toolchain: tc
        } if v_num.present?
      end

      version_numbers = versions.map { |v| v[:version] }.uniq

      {
        name: pkg_name,
        description: desc,
        homepage: homepage,
        repository_url: repo_fallback('', homepage),
        licenses: nil,
        version: version_numbers.last,
        versions: version_numbers,
        versions_detail: versions
      }
    rescue StandardError => e
      Rails.logger.error "Easybuild#fetch_package_metadata_uncached failed for #{name}: #{e.message}"
      nil
    end

    def map_package_metadata(package)
      return false if package.blank?

      package
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      return [] if pkg_metadata.blank? || pkg_metadata[:versions].blank?

      pkg_metadata[:versions].map do |ver|
        details = (pkg_metadata[:versions_detail] || []).select { |vd| vd[:version] == ver }
        toolchains = details.map { |d| d[:toolchain] }.compact
        {
          number: ver,
          metadata: {
            toolchains: toolchains
          }.compact
        }
      end
    end

    def dependencies_metadata(name, version, _package = nil)
      eb_url = "https://raw.githubusercontent.com/easybuilders/easybuild-easyconfigs/develop/easybuild/easyconfigs/#{letter_path(name)}/#{name}/#{name}-#{version}.eb"
      eb_content = get_raw_no_exception(eb_url)
      return [] if eb_content.blank?

      parsed = EasyconfigParser.parse(eb_content)
      (parsed[:dependencies] || []).map do |dep|
        {
          package_name: dep[:name],
          requirements: dep[:version] || '*',
          kind: dep[:kind] || 'runtime',
          ecosystem: 'easybuild'
        }
      end
    rescue StandardError => e
      Rails.logger.error "Easybuild#dependencies_metadata failed: #{e.message}"
      []
    end

    def letter_path(name)
      first_char = name.to_s[0]
      return '0' if first_char =~ /\A[0-9]\z/

      first_char.to_s.downcase
    end
  end
end
