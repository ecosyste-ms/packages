# frozen_string_literal: true

module Ecosystem
  class Easybuild < Base
    def registry_url(package, _version = nil)
      letter = package.name[0].downcase
      letter = '0' if letter.match?(/\d/)
      letter = '0' unless letter.match?(/[a-z]/)
      "#{@registry_url.chomp('/')}/#{letter}/#{package.name}/"
    end

    def install_command(package, version = nil)
      v = version.is_a?(Version) ? version.number : version
      if v.present?
        "eb #{package.name}-#{v}.eb --robot"
      else
        "eb #{package.name} --robot"
      end
    end

    def check_status_url(package)
      registry_url(package)
    end

    def check_status(package)
      pkg = fetch_package_metadata(package.name)
      return nil if pkg.present? && pkg.is_a?(Hash) && (pkg['name'].present? || pkg[:name].present?)

      url = check_status_url(package)
      response = Faraday.head(url)
      return 'removed' if [400, 404, 410].include?(response.status)
    rescue StandardError
      nil
    end

    def all_package_names
      doc = get_html(@registry_url)
      names = []
      doc.css('article a, main a').each do |a|
        href = a['href']
        next unless href
        m = href.match(%r{\A([0-9a-z])\/([^\/]+)\/?\z})
        names << m[2] if m
      end
      names.uniq.sort
    rescue StandardError
      []
    end

    def recently_updated_package_names
      u = 'https://github.com/easybuilders/easybuild-easyconfigs/commits/develop.atom'
      titles = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      titles.flat_map do |title|
        names = title.scan(/([A-Za-z0-9_\-+]+?)-[0-9]/).flatten
        if names.empty?
          if (m = title.match(/new_pr_([A-Za-z0-9_\-+]+?)\d+/))
            names << m[1]
          elsif (m = title.match(/feature-([A-Za-z0-9_\-+]+)_/))
            names << m[1]
          end
        end
        names
      end.uniq.compact
    rescue StandardError
      []
    end

    def fetch_package_metadata_uncached(name)
      pkg = Package.new(name: name)
      url = registry_url(pkg)
      doc = get_html(url)
      article = doc.at_css('article') || doc.at_css('main')
      return {} unless article.present?

      title_el = article.at_css('h1')
      pkg_name = title_el ? title_el.text.strip.sub(/[\u0000-\u0020\u00A0\u200B-\u200D\uFEFF\uFFFD]+$/, '') : name

      description = nil
      homepage = nil
      article.css('p').each do |p|
        text = p.text.strip
        if text.downcase.start_with?('homepage:') || p.at_css('em')&.text&.downcase&.include?('homepage')
          link = p.at_css('a')
          homepage = link['href'] if link
        elsif description.nil? && !text.downcase.start_with?('(quick links:')
          description = text unless text.blank?
        end
      end

      versions = []
      article.css('table tbody tr').each do |tr|
        cols = tr.css('td').map(&:text).map(&:strip)
        next if cols.empty?
        version = cols[0]
        toolchain = cols[1]
        versions << { 'version' => version, 'toolchain' => toolchain }
      end

      {
        'name' => pkg_name,
        'description' => description,
        'homepage' => homepage,
        'versions' => versions
      }
    rescue StandardError
      {}
    end

    def map_package_metadata(package)
      return false unless package.present?
      name = package['name'] || package[:name]
      return false if name.blank?

      description = package['description'] || package[:description]
      homepage = package['homepage'] || package[:homepage]
      versions = package['versions'] || package[:versions] || []

      latest_version = versions.last.is_a?(Hash) ? (versions.last['version'] || versions.last[:version]) : versions.last

      {
        name: name,
        description: description,
        homepage: homepage,
        repository_url: repo_fallback(homepage, homepage),
        licenses: [],
        version: latest_version,
        versions: versions
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      return [] unless pkg_metadata.present?
      versions = pkg_metadata[:versions] || pkg_metadata['versions']
      return [] unless versions.present?

      versions_by_num = {}
      versions.each do |item|
        num = item.is_a?(Hash) ? (item['version'] || item[:version]) : item
        toolchain = item.is_a?(Hash) ? (item['toolchain'] || item[:toolchain]) : nil
        next if num.blank?

        versions_by_num[num] ||= {
          number: num,
          metadata: { toolchains: [] }
        }
        if toolchain.present? && !versions_by_num[num][:metadata][:toolchains].include?(toolchain)
          versions_by_num[num][:metadata][:toolchains] << toolchain
        end
      end

      versions_by_num.values
    rescue StandardError
      []
    end
  end
end
