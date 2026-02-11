module Ecosystem
  class Go < Base

    def self.purl_type
      'golang'
    end

    def purl_params(package, version = nil)
      namespace = encode_for_proxy package.name.split('/')[0..-2].join('/')
      name = encode_for_proxy package.name.split('/').last
      {
        type: purl_type,
        namespace: namespace,
        name: name,
        version: version.try(:number).try(:encode,'iso-8859-1')
      }
    end


    def registry_url(package, version = nil)
      "https://pkg.go.dev/#{package.name}#{"@#{version}" if version}"
    end

    def documentation_url(package, version = nil)
      "https://pkg.go.dev/#{package.name}#{"@#{version}" if version}#section-documentation"
    end

    def check_status(package)
      url = "https://pkg.go.dev/#{package.name}"
      response = Faraday.head(url)
      if [400, 404, 410, 302, 301].include?(response.status)
        proxy_url = "#{@registry_url}/#{encode_for_proxy(package.name)}/@v/list"
        response = Faraday.get(proxy_url)
        if [400, 404, 410].include?(response.status) || response.body.length.zero?
          "removed"
        end
      end
    end

    def install_command(package, version = nil)
      "go get #{package.name}#{"@#{version}" if version}"
    end

    def download_url(package, version)
      return nil unless version.present?
      "#{@registry_url}/#{encode_for_proxy(package.name)}/@v/#{version}.zip"
    end

    def all_package_names
      names = []
      pkgs = get_raw("https://index.golang.org/index").split("\n").map{|row| Oj.load(row)}
      names += pkgs.map{|j| j['Path' ]}
      since = pkgs.last['Timestamp']

      while 
        pkgs = get_raw("https://index.golang.org/index?since=#{since}").split("\n").map{|row| Oj.load(row)}
        break if pkgs.last['Timestamp'] == since
        since = pkgs.last['Timestamp']
        names += pkgs.map{|j| j['Path' ]}
      end

      names.uniq
    rescue
      []
    end

    def recently_updated_package_names
      get_raw("https://index.golang.org/index?since=#{Time.now.utc.beginning_of_day.to_fs(:iso8601)}").split("\n").map{|row| Oj.load(row)['Path']}.uniq
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      resp = request("https://pkg.go.dev/#{name}")

      if resp.success?
        doc_html = Nokogiri::HTML(resp.body)
        { name: name, html: doc_html, overview_html: doc_html }
      else
        resp = request("#{@registry_url}/#{encode_for_proxy(name)}/@v/list")
        if resp.success? && resp.body.length > 0
          { name: name, repository_url: UrlParser.try_all(name) }
        else
          false
        end
      end
    rescue
      false
    end

    def map_package_metadata(package)
      return false unless package
      if package[:html]
        url = package[:overview_html]&.css(".UnitMeta-repo a")&.first&.attribute("href")&.value

        {
          name: package[:name],
          description: package[:html].css(".Documentation-overview p").map(&:text).join("\n").strip,
          licenses: package[:html].css('*[data-test-id="UnitHeader-license"]').map(&:text).join(","),
          repository_url: url,
          homepage: url,
          namespace: package[:name].split('/')[0..-2].join('/')
        }
      else
        { name: package[:name], repository_url: UrlParser.try_all(package[:name]) }
      end
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      resp = request("#{@registry_url}/#{encode_for_proxy(pkg_metadata[:name])}/@v/list")
      html_resp = get_html("https://pkg.go.dev/#{pkg_metadata[:name]}?tab=versions")

      retracted_version_numbers = fetch_all_retracted_version_numbers(existing_version_numbers, html_resp)
      existing_version_numbers = existing_version_numbers - retracted_version_numbers

      if resp.success?
        text = resp.body
        versions = text.split("\n").map(&:strip).reject(&:empty?)
      else
        versions = []
      end

      if versions.any?
        versions.reject{|v| existing_version_numbers.include?(v)}.sort.reverse.first(50).map do |v|
          {
            number: v,
            published_at: get_version(pkg_metadata[:name], v).fetch('Time',nil),
            status: fetch_version_status(html_resp, v)
          }
        end
      else
        versions_fallback(pkg_metadata, existing_version_numbers, html_resp)
      end

    rescue StandardError
      []
    end

    def versions_fallback(package, existing_version_numbers = [], html_resp = nil)
      html_resp ||= get_html("https://pkg.go.dev/#{package[:name]}?tab=versions")

      html_resp.css(".Version-tag a").first(50).map do |link|
        next if existing_version_numbers.include?(link.text)
        {
          number: link.text,
          published_at: get_version(package[:name], link.text).fetch('Time',nil),
          status: fetch_version_status(html_resp, link.text)
        }
      end.compact
    end

    def fetch_version_status(html_resp, version_number)
      html_resp.css(".Version-tag a").each do |link|
        return link.parent.css('~ .Version-commitTime').first&.css('.go-Chip')&.text&.presence if link.text == version_number
      end
      nil
    end

    def fetch_all_retracted_version_numbers(existing_version_numbers, html_resp)
      existing_version_numbers.select do |version_number|
        fetch_version_status(html_resp, version_number) == "retracted"
      end
    end

    def dependencies_metadata(name, version, _package)
      # Go proxy spec: https://golang.org/cmd/go/#hdr-Module_proxy_protocol
      # TODO: this can take up to 2sec if it's a cache miss on the proxy. Might be able
      # to scrape the webpage or wait for an API for a faster fetch here.
      resp = request("#{@registry_url}/#{encode_for_proxy(name)}/@v/#{version}.mod")
      if resp.status == 200
        go_mod_file = resp.body
        result = Bibliothecary::Parsers::Go.parse_go_mod(go_mod_file)
        dependencies = result.is_a?(Bibliothecary::ParserResult) ? result.dependencies : result
        dependencies.map do |dep|
          dep_hash = dep.is_a?(Bibliothecary::Dependency) ? dep.to_h : dep
          {
            package_name: dep_hash[:name],
            requirements: dep_hash[:requirement].try(:delete, "\u0000"),
            kind: dep_hash[:type],
            ecosystem: self.class.name.demodulize.downcase,
          }
        end
      else
        []
      end
    end

    def get_version(package_name, version)
      get_json("#{@registry_url}/#{encode_for_proxy(package_name)}/@v/#{version}.info") rescue {}
    end

    # will convert a string with capital letters and replace with a "!" prepended to the lowercase letter
    # this is needed to follow the goproxy protocol and find versions correctly for modules with capital letters in them
    # https://go.dev/ref/mod#goproxy-protocol
    def encode_for_proxy(str)
      return '' if str.nil?
      str.gsub(/[A-Z]/) { |s| "!#{s.downcase}" }
    end
  end
end
