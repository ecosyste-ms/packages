module Ecosystem
  class Go < Base
    PKGSITE_API = "https://pkg.go.dev/v1beta"
    INDEX_API = "https://index.golang.org/index"
    INDEX_PAGE_SIZE = 2_000
    SYNC_MISSING_CURSOR_KEY = "sync_missing_packages_cursor"
    DEFAULT_PROXY_URL = "https://proxy.golang.org/cached-only"

    def proxy_url
      ENV.fetch('GO_PROXY_URL', DEFAULT_PROXY_URL).delete_suffix('/')
    end

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
      meta = fetch_package_metadata(package.name)
      return nil if meta.is_a?(Hash) && meta[:name].present?
      return "removed" if meta == false
      nil
    end

    def install_command(package, version = nil)
      "go get #{package.name}#{"@#{version}" if version}"
    end

    def download_url(package, version)
      return nil unless version.present?
      "#{proxy_url}/#{encode_for_proxy(module_path_for(package))}/@v/#{encode_for_proxy(version.to_s)}.zip"
    end

    def sync_missing_packages_incrementally?
      true
    end

    def sync_missing_packages_async
      cursor = sync_missing_packages_cursor
      latest_by_path = {}
      next_cursor = cursor

      loop do
        rows = index_versions(cursor)
        break if rows.empty?

        new_rows = index_versions_after_cursor(rows, cursor)
        break if new_rows.empty?

        new_rows.each do |row|
          latest_by_path[row["Path"]] = row if row["Path"].present? && row["Version"].present?
        end
        next_cursor = index_cursor_for(new_rows.last)
        break if rows.length < INDEX_PAGE_SIZE || next_cursor == cursor

        cursor = next_cursor
      end

      enqueued = enqueue_missing_package_versions(latest_by_path)
      save_sync_missing_packages_cursor(next_cursor)
      enqueued
    rescue => e
      Rails.logger.error("Error syncing missing Go packages for registry #{@registry.id}: #{e.message}")
      0
    end

    def sync_missing_packages_cursor
      cursor = @registry.metadata.to_h[SYNC_MISSING_CURSOR_KEY]
      return cursor if cursor.is_a?(Hash) && cursor["timestamp"].present?

      {"timestamp" => 1.day.ago.utc.iso8601(9)}
    end

    def index_versions(cursor)
      url = "#{INDEX_API}?since=#{cursor.fetch("timestamp")}&limit=#{INDEX_PAGE_SIZE}"
      response = request(url)
      raise "Go index returned #{response.status}" unless response.success?

      response.body.split("\n").filter_map do |row|
        Oj.load(row) unless row.blank?
      end
    end

    def index_versions_after_cursor(rows, cursor)
      return rows unless cursor["path"].present? && cursor["version"].present?

      cursor_index = rows.index do |row|
        row["Timestamp"] == cursor["timestamp"] &&
          row["Path"] == cursor["path"] &&
          row["Version"] == cursor["version"]
      end
      cursor_index ? rows.drop(cursor_index + 1) : rows
    end

    def enqueue_missing_package_versions(latest_by_path)
      return 0 if latest_by_path.empty?

      existing_names = Set.new
      latest_by_path.keys.each_slice(1_000) do |names|
        existing_names.merge(@registry.packages.where(name: names).pluck(:name))
      end

      jobs = latest_by_path.filter_map do |name, row|
        [@registry.id, name, row["Version"]] unless existing_names.include?(name)
      end
      jobs.each_slice(1_000) { |batch| SyncPackageVersionWorker.perform_bulk(batch) }
      jobs.length
    end

    def index_cursor_for(row)
      {
        "timestamp" => row.fetch("Timestamp"),
        "path" => row.fetch("Path"),
        "version" => row.fetch("Version")
      }
    end

    def save_sync_missing_packages_cursor(cursor)
      metadata = @registry.metadata.to_h.merge(SYNC_MISSING_CURSOR_KEY => cursor)
      @registry.update!(metadata: metadata)
    end

    def all_package_names
      names = []
      pkgs = get_raw(INDEX_API).split("\n").map{|row| Oj.load(row)}
      names += pkgs.map{|j| j['Path' ]}
      since = pkgs.last['Timestamp']

      while 
        pkgs = get_raw("#{INDEX_API}?since=#{since}").split("\n").map{|row| Oj.load(row)}
        break if pkgs.last['Timestamp'] == since
        since = pkgs.last['Timestamp']
        names += pkgs.map{|j| j['Path' ]}
      end

      names.uniq
    rescue
      []
    end

    def recently_updated_package_names
      get_raw("#{INDEX_API}?since=#{Time.now.utc.beginning_of_day.to_fs(:iso8601)}").split("\n").map{|row| Oj.load(row)['Path']}.uniq
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      package = fetch_package_metadata_from_pkgsite(name)
      return package if package

      resp = request("#{proxy_url}/#{encode_for_proxy(name)}/@v/list")
      if resp.success? && resp.body.length > 0
        { name: name, repository_url: UrlParser.try_all(name) }
      else
        false
      end
    rescue
      false
    end

    def fetch_package_metadata_from_pkgsite(name)
      resp = request("#{PKGSITE_API}/module/#{name}?licenses=true")
      if resp.success?
        mod = Oj.load(resp.body)
        return { name: name, module: mod, synopsis: fetch_synopsis(name) }
      end

      package = fetch_pkgsite_package(name)
      module_path = package&.fetch('modulePath', nil)
      return nil if module_path.blank? || module_path == name

      resp = request("#{PKGSITE_API}/module/#{module_path}?licenses=true")
      return nil unless resp.success?

      {
        name: name,
        module: Oj.load(resp.body),
        module_path: module_path,
        synopsis: package['synopsis'],
        version: package['version']
      }
    rescue
      nil
    end

    def fetch_package_metadata_for_version(name, version)
      resp = request("#{proxy_url}/#{encode_for_proxy(name)}/@v/#{encode_for_proxy(version)}.mod")
      return false if [400, 404, 410].include?(resp.status)
      raise "Go proxy returned #{resp.status} for #{name}@#{version}.mod" unless resp.success?

      declared_name = module_path_from_go_mod(resp.body)
      if declared_name.blank?
        Rails.logger.warn("Go module #{name}@#{version} has no module directive")
        return false
      end
      if declared_name != name
        Rails.logger.info("Ignoring alternative Go module path #{name}@#{version}; go.mod declares #{declared_name}")
        return false
      end

      package = fetch_package_metadata_from_pkgsite(name)
      package ||= { name: name, repository_url: UrlParser.try_all(name) }
      package.merge(version: version)
    end

    def module_path_from_go_mod(contents)
      contents.each_line do |line|
        match = line.match(/\A\s*module\s+(?:"([^"]+)"|`([^`]+)`|(\S+))/)
        return match.captures.compact.first if match
      end
      nil
    end

    def fetch_synopsis(name)
      fetch_pkgsite_package(name)&.fetch('synopsis', nil)
    end

    def fetch_pkgsite_package(name)
      resp = request("#{PKGSITE_API}/package/#{name}")
      return nil unless resp.success?
      Oj.load(resp.body)
    rescue
      nil
    end

    def map_package_metadata(package)
      return false unless package
      metadata = if package[:module]
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
      if package[:module_path].present? && package[:module_path] != package[:name]
        metadata[:metadata] = { 'module_path' => package[:module_path] }
      elsif package[:module]
        metadata[:metadata] = nil
      end
      metadata[:version] = package[:version] if package[:version].present?
      metadata
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      name = module_path_for(pkg_metadata)
      subpackage = name != pkg_metadata[:name]
      relevant_versions = Set.new(existing_version_numbers)
      relevant_versions << pkg_metadata[:version] if pkg_metadata[:version].present?
      items = fetch_all_versions(name)
      versions = if items.empty?
                   versions_from_proxy(
                     name,
                     subpackage ? [] : existing_version_numbers,
                     only: subpackage ? relevant_versions : nil
                   )
                 else
                   items.filter_map do |item|
                     next unless item['modulePath'] == name
                     next if subpackage && !relevant_versions.include?(item['version'])
                     status = version_status(item)
                     next if !subpackage && existing_version_numbers.include?(item['version']) && status.nil?

                     {
                       number: item['version'],
                       published_at: item['commitTime'],
                       status: status
                     }
                   end
                 end

      discovered_version = pkg_metadata[:version]
      if discovered_version.present? &&
          (subpackage || !existing_version_numbers.include?(discovered_version)) &&
          versions.none? { |item| item[:number] == discovered_version }
        versions << {
          number: discovered_version,
          published_at: get_version(name, discovered_version).fetch('Time', nil),
          status: nil
        }
      end
      versions
    rescue StandardError
      []
    end

    def update_existing_versions(package, versions_metadata)
      return if package.metadata.to_h['module_path'].blank?

      active_numbers = versions_metadata.filter_map do |version|
        version = version.with_indifferent_access
        version[:number].to_s if version[:status].nil?
      end
      return if active_numbers.empty?

      package.versions.where(number: active_numbers, status: 'removed')
        .update_all(status: nil, updated_at: Time.current)
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

    def versions_from_proxy(name, existing_version_numbers, only: nil)
      resp = request("#{proxy_url}/#{encode_for_proxy(name)}/@v/list")
      return [] unless resp.success?

      resp.body.split("\n").map(&:strip).reject(&:empty?)
        .select { |v| only.nil? || only.include?(v) }
        .reject { |v| existing_version_numbers.include?(v) }
        .sort.reverse.first(50).map do |v|
          {
            number: v,
            published_at: get_version(name, v).fetch('Time', nil),
            status: nil
          }
        end
    end

    def dependencies_metadata(name, version, package_metadata)
      # Go proxy spec: https://golang.org/cmd/go/#hdr-Module_proxy_protocol
      name = module_path_for(package_metadata) if package_metadata
      resp = request("#{proxy_url}/#{encode_for_proxy(name)}/@v/#{encode_for_proxy(version)}.mod")
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
      get_json("#{proxy_url}/#{encode_for_proxy(package_name)}/@v/#{encode_for_proxy(version)}.info") rescue {}
    end

    def module_path_for(package)
      package[:metadata].to_h['module_path'].presence || package[:name]
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
