# frozen_string_literal: true

module Ecosystem
  class Hackage < Base
    def registry_url(package, version = nil)
      "#{@registry_url}/package/#{package.name}" + (version ? "-#{version}" : "")
    end

    def download_url(package, version)
      return nil unless version.present?
      "#{@registry_url}/package/#{package.name}-#{version}/#{package.name}-#{version}.tar.gz"
    end

    def install_command(package, version = nil)
      "cabal install #{package.name}" + (version ? "-#{version}" : "")
    end

    def all_package_names
      get_html("#{@registry_url}/packages/names").css('.packages a:first').map(&:text)
    rescue
      []
    end

    def recently_updated_package_names
      u = "#{@registry_url}/packages/recent.rss"
      titles = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      titles.map { |t| t.split(" ").first }.uniq
    rescue
      []
    end

    def fetch_package_metadata(name)
      page = get_html("#{@registry_url}/package/#{name}", headers: { "Accept" => "text/html" })
      return nil unless page.css('#content div').first
      {
        name: name,
        page: page
      }
    rescue
      nil
    end

    def map_package_metadata(package)
      return nil if package.nil?
      {
        name: package[:name],
        keywords_array: Array(package[:page].css('#content div').first.css('a')[0..-2].map(&:text)),
        description: description(package[:page]),
        licenses: find_attribute(package[:page], "License"),
        homepage: find_attribute(package[:page], "Home page"),
        repository_url: repo_fallback(repository_url(find_attribute(package[:page], "Source repository")), find_attribute(package[:page], "Home page")),
        page: package[:page],
        downloads: find_attribute(package[:page], "Downloads").split(' ').first.to_i,
        downloads_period: 'total'
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      versions = find_attribute(pkg_metadata[:page], "Versions")
      versions = find_attribute(pkg_metadata[:page], "Version") if versions.nil?
      versions.delete("(info)").split(",").map(&:strip).map do |v|
        {
          number: v,
        }
      end
    end

    def dependencies_metadata(name, version, _package)
      page = get_html("#{@registry_url}/package/#{name}-#{version}", headers: { "Accept" => "text/html" })
      return [] if page.nil?
      deps = find_attribute(page, "Dependencies")
      deps.gsub!('[details]', '')
      deps.split(',').map do |dep|
        parts = dep.split(' ')
        package_name = parts[0]
        requirements = parts[1..-1].join(' ').gsub('(','').gsub(')','')
        {
          package_name: package_name,
          requirements: requirements.presence || '*',
          kind: 'runtime',
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end

    def find_attribute(page, name)
      tr = page.css("#content tr").select { |t| t.css("th").text.to_s.start_with?(name) }.first
      tr&.css("td")&.text&.strip 
    end

    def description(page)
      contents = page.css("#content p, #content hr").map(&:text)
      index = contents.index ""
      return "" unless index

      contents[0..(index - 1)].join("\n\n")
    end

    def repository_url(text)
      return nil unless text.present?

      match = text.match(/github.com\/(.+?)\.git/)
      return nil unless match

      "https://github.com/#{match[1]}"
    end

    def maintainers_metadata(name)
      page = get_html("#{@registry_url}/package/#{name}/maintainers", headers: { "Accept" => "text/html" })
      return [] if page.nil?
      page.css('#content ul a').map do |a|
        {
          uuid: a.text,
          login: a.text
        }
      end
    end
  end
end
