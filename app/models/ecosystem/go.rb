module Ecosystem
  class Go < Base
    PKGSITE_API = "https://pkg.go.dev/v1beta"

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
      resp = request("#{PKGSITE_API}/module/#{name}?licenses=true")

      if resp.success?
        mod = Oj.load(resp.body)
        { name: name, module: mod, synopsis: fetch_synopsis(name) }
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

    def fetch_synopsis(name)
      resp = request("#{PKGSITE_API}/package/#{name}")
      return nil unless resp.success?
      Oj.load(resp.body)['synopsis']
    rescue
      nil
    end

    def map_package_metadata(package)
      return false unless package
      if package[:module]
        mod = package[:module]
        url = mod['repoUrl']
        licenses = Array(mod['licenses']).flat_map { |l| l['types'] }.compact.uniq.join(',')

        {
          name: package[:name],
          description: package[:synopsis],
          licenses: licenses,
          repository_url: url,
          homepage: url,
          namespace: package[:name].split('/')[0..-2].join('/')
        }
      else
        { name: package[:name], repository_url: UrlParser.try_all(package[:name]) }
      end
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      name = pkg_metadata[:name]
      items = fetch_all_versions(name)
      return versions_from_proxy(name, existing_version_numbers) if items.empty?

      items.filter_map do |item|
        next unless item['modulePath'] == name
        status = version_status(item)
        next if existing_version_numbers.include?(item['version']) && status.nil?

        {
          number: item['version'],
          published_at: item['commitTime'],
          status: status
        }
      end
    rescue StandardError
      []
    end

    def fetch_all_versions(name)
      items = []
      token = nil
      loop do
        url = "#{PKGSITE_API}/versions/#{name}?limit=1000"
        url += "&token=#{token}" if token
        resp = request(url)
        return items unless resp.success?
        page = Oj.load(resp.body)
        items.concat(Array(page['items']))
        token = page['nextPageToken']
        break if token.blank?
      end
      items
    end

    def version_status(item)
      return 'retracted' if item['retracted']
      return 'deprecated' if item['deprecated']
      nil
    end

    def versions_from_proxy(name, existing_version_numbers)
      resp = request("#{@registry_url}/#{encode_for_proxy(name)}/@v/list")
      return [] unless resp.success?

      resp.body.split("\n").map(&:strip).reject(&:empty?)
        .reject { |v| existing_version_numbers.include?(v) }
        .sort.reverse.first(50).map do |v|
          {
            number: v,
            published_at: get_version(name, v).fetch('Time', nil),
            status: nil
          }
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
