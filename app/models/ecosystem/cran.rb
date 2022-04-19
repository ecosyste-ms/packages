# frozen_string_literal: true

module Ecosystem
  class Cran < Base
    def registry_url(package, _version = nil)
      "https://cran.r-project.org/package=#{package.name}"
    end

    def download_url(name, version = nil)
      "https://cran.r-project.org/src/contrib/#{name}_#{version}.tar.gz"
    end

    def documentation_url(name, _version = nil)
      "http://cran.r-project.org/web/packages/#{name}/#{name}.pdf"
    end

    def check_status_url(package)
      "http://cran.r-project.org/web/packages/#{package.name}/index.html"
    end

    def all_package_names
      html = get_html("https://cran.r-project.org/web/packages/available_packages_by_date.html")
      html.css("tr")[1..-1].map { |tr| tr.css("td")[1].text.strip }
    end

    def recently_updated_package_names
      all_package_names.uniq.first(100)
    end

    def fetch_package_metadata(name)
      html = get_html("https://cran.r-project.org/web/packages/#{name}/index.html")
      properties = {}
      table = html.css("table")[0]
      return nil if table.nil?

      table.css("tr").each do |tr|
        tds = tr.css("td").map(&:text)
        properties[tds[0]] = tds[1]
      end

      { name: name, html: html, properties: properties }
    end

    def map_package_metadata(package)
      {
        name: package[:name],
        homepage: package[:properties].fetch("URL:", "").split(",").first,
        description: package[:html].css("h2").text.split(":")[1..-1].join(":").strip,
        licenses: package[:properties]["License:"],
        repository_url: repo_fallback("", (package[:properties].fetch("URL:", "").split(",").first.presence || package[:properties]["BugReports:"])).to_s[0, 255],
        properties: package[:properties]
      }
    end

    def versions_metadata(package)
      [{
        number: package[:properties]["Version:"],
        published_at: package[:properties]["Published:"],
      }] + find_old_versions(package)
    end

    def find_old_versions(package)
      archive_page = get_html("https://cran.r-project.org/src/contrib/Archive/#{package[:name]}/")
      trs = archive_page.css("table").css("tr").select do |tr|
        tds = tr.css("td")
        tds[1]&.text&.match(/tar\.gz$/)
      end
      trs.map do |tr|
        tds = tr.css("td")
        {
          number: tds[1].text.strip.split("_").last.gsub(".tar.gz", ""),
          published_at: tds[2].text.strip,
        }
      end
    end

    def dependencies_metadata(name, version, mapped_package)
      find_and_map_dependencies(name, version, mapped_package)
    end

    def find_dependencies(name, version)
      begin
        url = "https://cran.rstudio.com/src/contrib/#{name}_#{version}.tar.gz"
        head_response = Typhoeus.head(url)
        raise if head_response.code != 200
      rescue StandardError
        url = "https://cran.rstudio.com/src/contrib/Archive/#{name}/#{name}_#{version}.tar.gz"
      end

      folder_name = "#{name}_#{version}"
      tarball_name = "#{folder_name}.tar.gz"
      downloaded_file = File.open "/tmp/#{tarball_name}", "wb"
      request = Typhoeus::Request.new(url)
      request.on_headers do |response|
        return [] if response.code != 200
      end
      request.on_body { |chunk| downloaded_file.write(chunk) }
      request.on_complete { downloaded_file.close }
      request.run

      cmd = `mkdir /tmp/#{folder_name} && tar xzf /tmp/#{tarball_name} -C /tmp/#{folder_name}  --strip-components 1`

      contents = `cat /tmp/#{folder_name}/DESCRIPTION`

      `rm -rf /tmp/#{folder_name}` if folder_name.present?
      `rm -rf /tmp/#{tarball_name}` if tarball_name.present?

      Bibliothecary.analyse_file("DESCRIPTION", contents).first.fetch(:dependencies)
    ensure
      `rm -rf /tmp/#{folder_name}` if folder_name.present?
      `rm -rf /tmp/#{tarball_name}` if tarball_name.present?
      []
    end
  end
end
