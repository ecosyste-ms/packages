module Ecosystem
  class Go < Base
    def package_url(package, version = nil)
      "https://pkg.go.dev/#{package.name}#{"@#{version}" if version}"
    end

    def documentation_url(name, version = nil)
      "https://pkg.go.dev/#{name}#{"@#{version}" if version}#section-documentation"
    end

    def install_command(package, version = nil)
      "go get #{package.name}#{"@#{version}" if version}"
    end

    def download_url(name, version)
      "#{@registry_url}/#{name}/@v/#{version}.zip"
    end

    def all_package_names
      names = []
      pkgs = get_raw("https://index.golang.org/index").split("\n").map{|row| JSON.parse(row)}
      names += pkgs.map{|j| j['Path' ]}
      since = pkgs.last['Timestamp']

      while 
        pkgs = get_raw("https://index.golang.org/index?since=#{since}").split("\n").map{|row| JSON.parse(row)}
        break if pkgs.last['Timestamp'] == since
        since = pkgs.last['Timestamp']
        names += pkgs.map{|j| j['Path' ]}
      end

      names.uniq
    end

    def recently_updated_package_names
      get_raw("https://index.golang.org/index?since=#{Time.now.beginning_of_day.to_fs(:iso8601)}").split("\n").map{|row| JSON.parse(row)['Path']}
    end

    def fetch_package_metadata(name)
      # get_html will send back an empty string if response is not a 200
      # a blank response means that the package was not found on pkg.go.dev site
      # if it is not found on that site it should be considered an invalid package name
      # although the go proxy may respond with data for this package name
      doc_html = get_html("https://pkg.go.dev/#{name}")

      # send back nil if the response is blank
      # base package manager handles if the package is not present
      { name: name, html: doc_html, overview_html: doc_html } unless doc_html.text.blank?
    end

    def map_package_metadata(raw_package)
      if raw_package[:html]
        url = raw_package[:overview_html]&.css(".UnitMeta-repo a")&.first&.attribute("href")&.value

        {
          name: raw_package[:name],
          description: raw_package[:html].css(".Documentation-overview p").map(&:text).join("\n").strip,
          licenses: raw_package[:html].css('*[data-test-id="UnitHeader-license"]').map(&:text).join(","),
          repository_url: url,
          homepage: url,
        }
      else
        { name: raw_package[:name] }
      end
    end

    def versions_metadata(raw_package)
      txt = get_raw("#{@registry_url}/#{raw_package[:name]}/@v/list")
      versions = txt.split("\n")

      versions.map do |v|
        {
          number: v,
          published_at: get_version(raw_package[:name], v).fetch('Time')
        }
      end
    rescue StandardError
      []
    end

    def dependencies_metadata(name, version, _mapped_package)
      # Go proxy spec: https://golang.org/cmd/go/#hdr-Module_proxy_protocol
      # TODO: this can take up to 2sec if it's a cache miss on the proxy. Might be able
      # to scrape the webpage or wait for an API for a faster fetch here.
      resp = request("#{@registry_url}/#{encode_for_proxy(name)}/@v/#{version}.mod")
      if resp.status == 200
        go_mod_file = resp.body
        Bibliothecary::Parsers::Go.parse_go_mod(go_mod_file)
          .map do |dep|
            {
              package_name: dep[:name],
              requirements: dep[:requirement],
              kind: dep[:type],
              platform: "Go",
            }
          end
      else
        []
      end
    end

    def get_repository_url(package_name)
      res = request("https://#{package_name}")
      res.env.url.to_s if res.success?
    end

    def get_version(package_name, version)
      get_json("#{@registry_url}/#{package_name}/@v/#{version}.info")
    end

    # https://golang.org/cmd/go/#hdr-Import_path_syntax
    def package_find_names(name)
      return [name] if name.start_with?(*KNOWN_HOSTS)
      return [name] if KNOWN_VCS.any?(&name.method(:include?))

      begin
        go_import = get_html("https://#{name}?go-get=1")
          .xpath('//meta[@name="go-import"]')
          .first
          &.attribute("content")
          &.value
          &.split(" ")
          &.last
          &.sub(/https?:\/\//, "")

        go_import&.start_with?(*KNOWN_HOSTS) ? [go_import] : [name]
      rescue StandardError
        [name]
      end
    end

    # will convert a string with capital letters and replace with a "!" prepended to the lowercase letter
    # this is needed to follow the goproxy protocol and find versions correctly for modules with capital letters in them
    # https://go.dev/ref/mod#goproxy-protocol
    def encode_for_proxy(str)
      str.gsub(/[A-Z]/) { |s| "!#{s.downcase}" }
    end

    def one_version(raw_package, version_string)
      info = get("#{@registry_url}/#{encode_for_proxy(raw_package[:name])}/@v/#{version_string}.info")

      # Store nil published_at for known Go Modules issue where case-insensitive name collisions break go get
      # e.g. #{@registry_url}/github.com/ysweid/aws-sdk-go/@v/v1.12.68.info
      version_string = info.nil? ? version_string : info["Version"]
      published_at = info && info["Time"].presence && Time.parse(info["Time"])
      data = {
        number: version_string,
        published_at: published_at,
      }

      # Supplement with license info from pkg.go.dev
      doc_html = get_html("https://pkg.go.dev/#{raw_package[:name]}")
      data[:original_license] = doc_html.css('*[data-test-id="UnitHeader-license"]').map(&:text).join(",")

      data
    end
  end
end
