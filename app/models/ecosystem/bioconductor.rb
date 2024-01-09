# frozen_string_literal: true

module Ecosystem
  class Bioconductor < Base
    def registry_url(package, _version = nil)
      "https://bioconductor.org/packages/#{package.name}"
    end

    def download_url(package, version)
      return nil unless version.present?
      "https://bioconductor.org/packages/release/bioc/src/contrib/#{package.name}_#{version}.tar.gz"
    end

    def documentation_url(package, _version = nil)
      "https://bioconductor.org/packages/release/bioc/vignettes/#{package.name}/inst/doc/#{package.name}.pdf"
    end

    def check_status_url(package)
      "https://www.bioconductor.org/packages/release/bioc/html/#{package.name}.html"
    end

    def all_package_names
      html = get_html("https://www.bioconductor.org/packages/release/bioc/")
      html.css("tr")[1..-1].map { |tr| tr.css("td")[0].text.strip }
    rescue
      []
    end

    def recently_updated_package_names
      []
    end

    def fetch_package_metadata(name)
      html = get_html("https://www.bioconductor.org/packages/release/bioc/html/#{name}.html")
      properties = {}
      table = html.css("h3#details + table")[0]
      return nil if table.nil?

      table.css("tr").each do |tr|
        tds = tr.css("td").map(&:text)
        properties[tds[0]] = tds[1]
      end

      { name: name, html: html, properties: properties }
    rescue
      nil
    end

    def map_package_metadata(package)
      return false unless package
      {
        name: package[:name],
        homepage: package[:properties].fetch("URL", "").split(",").first,
        description: package[:html].css("h2").text.strip,
        licenses: package[:properties]["License"],
        repository_url: repo_fallback(package[:properties].fetch("URL", "").split(",").first.presence, (package[:properties].fetch("URL", "").split(",").last.presence || package[:properties]["BugReports"])).to_s[0, 255],
        keywords_array: package[:properties]["biocViews"].split(", "),
        properties: package[:properties],
        downloads: downloads(package),
        downloads_period: "total",
      }
    end

    def downloads(package)
      response = get_raw("https://bioconductor.org/packages/stats/bioc/#{package[:name]}/#{package[:name]}_stats.tab")
      csv = CSV.parse response, col_sep: "\t", headers: true

      count = 0
      csv.each do |row|
        count += row["Nb_of_downloads"].to_i unless row['Month'] == 'all'
      end
      count
    rescue
      nil
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      [{
        number: pkg_metadata[:properties]["Version"],
      }]
    end

    def dependencies_metadata(name, version, mapped_package)
      find_and_map_dependencies(name, version, mapped_package)
    end

    def find_dependencies(name, version)
      url = "https://bioconductor.org/packages/release/bioc/src/contrib/#{name}_#{version}.tar.gz"

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

    def maintainers_metadata(name)
      pkg = fetch_package_metadata(name)
      return [] unless pkg
      maintainers = pkg[:html].css('p').find{|p| p.text.strip.starts_with? 'Maintainer'}.text.strip.gsub('Maintainer: ','').split(',')
      maintainers.map do |string|
        name, email = string.split(' <')
        next if email.nil?
        email = email.gsub('>','').gsub(' at ', '@')
        {
          uuid: email.strip,
          name: name.strip,
          email: email.strip
        }
      end.compact
    end
  end
end
