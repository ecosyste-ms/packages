# frozen_string_literal: true

module Ecosystem
  class Dub < Base
    REPOSITORY_HOSTS = {
      'github' => 'https://github.com',
      'gitlab' => 'https://gitlab.com',
      'bitbucket' => 'https://bitbucket.org',
      'forgejo' => 'https://codeberg.org',
    }.freeze

    def registry_url(package, version = nil)
      url = "#{@registry_url}/packages/#{package.name}"
      version ? "#{url}/#{version}" : url
    end

    def download_url(package, version = nil)
      return nil unless version.present?
      "#{@registry_url}/packages/#{package.name}/#{version}.zip"
    end

    def documentation_url(package, _version = nil)
      package.metadata&.dig('documentation_url')
    end

    def install_command(package, version = nil)
      "dub add #{package.name}" + (version ? "@#{version}" : '')
    end

    def all_package_names
      get_json_array("#{@registry_url}/packages/index.json")
    rescue StandardError
      []
    end

    def recently_updated_package_names
      page = get_html("#{@registry_url}/?sort=updated&limit=100")
      page.css('table tr td:first-child a[href^="packages/"]').map { |link| link['href'].delete_prefix('packages/') }.uniq
    rescue StandardError
      []
    end

    def fetch_package_metadata_uncached(name)
      response = request("#{@registry_url}/api/packages/#{ERB::Util.url_encode(name)}/info")
      return nil if [404, 410].include?(response.status)
      raise "DUB package info unavailable for #{name} (HTTP #{response.status})" unless response.success?
      Oj.load(response.body)
    end

    def map_package_metadata(pkg)
      return false unless pkg.is_a?(Hash) && pkg['name'].present?

      latest = latest_release(pkg) || {}
      repository_url = repository_url(pkg['repository'])
      {
        name: pkg['name'],
        description: latest['description'],
        homepage: latest['homepage'].presence,
        licenses: latest['license'],
        repository_url: repo_fallback(repository_url, latest['homepage']),
        keywords_array: Array(pkg['categories']),
        versions: Array(pkg['versions']),
        metadata: {
          documentation_url: pkg['documentationURL'].presence,
          date_added: pkg['dateAdded'].presence,
        }.compact
      }
    end

    def versions_metadata(pkg_metadata, _existing_version_numbers = [])
      Array(pkg_metadata[:versions]).map do |version|
        {
          number: version['version'],
          published_at: version['date'].presence,
          licenses: version['license'],
          metadata: {
            commit_id: version['commitID'].presence,
            branch: branch?(version) || nil,
            configurations: configurations(version['configurations']).presence,
            subpackages: subpackages(pkg_metadata[:name], version['subPackages']).presence,
            system_dependencies: version['systemDependencies'].presence,
          }.compact
        }
      end
    end

    def dependencies_metadata(_name, version, pkg_metadata)
      release = Array(pkg_metadata[:versions]).find { |entry| entry['version'] == version }
      return [] unless release

      dependencies = dependency_specs(release['dependencies']).map { |name, spec| map_dependency(name, spec, 'runtime') }
      declared = dependencies.map { |dependency| dependency[:package_name] }.to_set
      configurations(release['configurations']).each do |configuration|
        dependency_specs(configuration[:dependencies]).each do |name, spec|
          next unless declared.add?(name)
          dependencies << map_dependency(name, spec, 'configuration')
        end
      end
      dependencies
    end

    def repository_url(repository)
      return nil unless repository.is_a?(Hash)
      host = REPOSITORY_HOSTS[repository['kind']]
      return nil if host.nil? || repository['owner'].blank? || repository['project'].blank?
      "#{host}/#{repository['owner']}/#{repository['project']}"
    end

    private

    def branch?(version)
      version['version'].to_s.start_with?('~')
    end

    def latest_release(pkg)
      versions = Array(pkg['versions'])
      versions.reject { |version| branch?(version) }.max_by { |version| version['date'].to_s } || versions.max_by { |version| version['date'].to_s }
    end

    def dependency_specs(dependencies)
      dependencies.is_a?(Hash) ? dependencies : {}
    end

    def map_dependency(name, spec, kind)
      spec = { 'version' => spec } unless spec.is_a?(Hash)
      {
        package_name: name,
        requirements: spec['version'].presence || '*',
        kind: kind,
        optional: spec['optional'] == true,
        ecosystem: self.class.name.demodulize.downcase
      }
    end

    # Configurations select platform or build specific dependencies, so keep each one's conditions
    def configurations(configurations)
      Array(configurations).filter_map do |configuration|
        next unless configuration.is_a?(Hash) && configuration['name'].present?
        {
          name: configuration['name'],
          platforms: configuration['platforms'].presence,
          dependencies: configuration['dependencies'].presence,
        }.compact
      end
    end

    # Subpackages are published as "parent:child" and can be depended on by that full name
    def subpackages(parent, subpackages)
      Array(subpackages).filter_map do |subpackage|
        next { path: subpackage } if subpackage.is_a?(String)
        next unless subpackage.is_a?(Hash) && subpackage['name'].present?
        {
          name: "#{parent}:#{subpackage['name']}",
          description: subpackage['description'].presence,
          dependencies: subpackage['dependencies'].presence,
          configurations: configurations(subpackage['configurations']).presence,
        }.compact
      end
    end
  end
end
