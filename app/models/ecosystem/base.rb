# frozen_string_literal: true

module Ecosystem
  class Base
    attr_accessor :registry_url

    def initialize(registry_url)
      @registry_url = registry_url
    end

    def self.list
      @ecosystems ||= begin
        Dir[Rails.root.join("app", "models", "ecosystem", "*.rb")].sort.each do |file|
          require file unless file.match(/base\.rb$/)
        end
        Ecosystem.constants
          .reject { |ecosystem| ecosystem == :Base }
          .map { |sym| "Ecosystem::#{sym}".constantize }
          .sort_by(&:name)
      end
    end

    # def default_language
    #   Languages::Language.all.find { |l| l.color == color }.try(:name)
    # end

    def self.format_name(ecosystem)
      return nil if ecosystem.nil?

      find(ecosystem).to_s.demodulize
    end

    def self.find(ecosystem)
      list.find { |p| p.formatted_name.downcase == ecosystem.downcase }
    end

    def self.formatted_name
      to_s.demodulize
    end

    def package_url(_package, _version = nil)
      nil
    end

    def download_url(_name, _version = nil)
      nil
    end

    def documentation_url(_name, _version = nil)
      nil
    end

    def install_command(_package, _version = nil)
      nil
    end

    def download_registry_users(_name)
      nil
    end

    def registry_user_url(_login)
      nil
    end

    def check_status_url(package)
      package_url(package)
    end

    def ecosystem_name(ecosystem)
      find(ecosystem).try(:formatted_name) || ecosystem
    end

    def save(package)
      return unless package.present?

      mapped_package = mapping(package)
      mapped_package = mapped_package.delete_if { |_key, value| value.blank? } if mapped_package.present?
      return false unless mapped_package.present?

      dbpackage = Package.find_or_initialize_by({ name: mapped_package[:name], ecosystem: name.demodulize })
      if dbpackage.new_record?
        dbpackage.assign_attributes(mapped_package.except(:name, :releases, :versions, :version, :dependencies, :properties))
        dbpackage.save! if dbpackage.changed?
      else
        dbpackage.reformat_repository_url
        attrs = mapped_package.except(:name, :releases, :versions, :version, :dependencies, :properties)
        dbpackage.update(attrs)
      end

      if self::HAS_VERSIONS
        versions(package, dbpackage.name).each do |version|
          dbpackage.versions.create(version) unless dbpackage.versions.find { |v| v.number == version[:number] }
        end
      end

      save_dependencies(dbpackage, mapped_package) if self::HAS_DEPENDENCIES
      dbpackage.reload
      # dbpackage.download_registry_users
      dbpackage.last_synced_at = Time.now
      dbpackage.save
      dbpackage
    end

    def update(name)
      pkg = package(name)
      save(pkg) if pkg.present?
    rescue SystemExit, Interrupt
      exit 0
    rescue StandardError => e
      if ENV["RACK_ENV"] == "production"
        # Bugsnag.notify(e)
      else
        raise
      end
    end

    def import
      return if ENV["READ_ONLY"].present?

      package_names.each { |name| update(name) }
    end

    def import_recent
      return if ENV["READ_ONLY"].present?

      recently_updated_package_names.each { |name| update(name) }
    end

    def import_new
      return if ENV["READ_ONLY"].present?

      new_names.each { |name| update(name) }
    end

    def new_names
      names = package_names
      existing_names = []
      Package.ecosystem(name.demodulize).select(:id, :name).find_each { |package| existing_names << package.name }
      names - existing_names
    end

    def save_dependencies(package, mapped_package)
      name = mapped_package[:name]
      package.versions.includes(:dependencies).each do |version|
        next if version.dependencies.any?

        deps = begin
                 dependencies(name, version.number, mapped_package)
               rescue StandardError
                 []
               end
        next unless deps&.any? && version.dependencies.empty?

        deps.each do |dep|
          named_package_id = Package
            .find_best(self.name.demodulize, dep[:package_name].strip)
            &.id
          version.dependencies.create(dep.merge(package_id: named_package_id.try(:strip)))
        end
        version.set_runtime_dependencies_count
      end
    end

    def dependencies(_name, _version, _package)
      []
    end

    def map_dependencies(deps, kind, optional = false, ecosystem = name.demodulize)
      deps.map do |k, v|
        {
          package_name: k,
          requirements: v,
          kind: kind,
          optional: optional,
          ecosystem: ecosystem,
        }
      end
    end

    def find_and_map_dependencies(name, version, _package)
      dependencies = find_dependencies(name, version)
      return [] unless dependencies&.any?

      dependencies.map do |dependency|
        dependency = dependency.deep_stringify_keys
        {
          package_name: dependency["name"],
          requirements: dependency["requirement"] || "*",
          kind: dependency["type"],
          ecosystem: self.name.demodulize,
        }
      end
    end

    def repo_fallback(repo, homepage)
      repo = "" if repo.nil?
      homepage = "" if homepage.nil?
      repo_url = UrlParser.try_all(repo)
      homepage_url = UrlParser.try_all(homepage)
      if repo_url.present?
        repo_url
      elsif homepage_url.present?
        homepage_url
      else
        repo
      end
    end

    def package_find_names(package_name)
      [package_name]
    end

    def deprecation_info(_name)
      { is_deprecated: false, message: nil }
    end

    def dependents(name)
      []
    end

    private

    def get_raw(url, options = {})
      request(url, options).body
    end

    def request(url, options = {})
      connection = Faraday.new url.strip, options do |builder|
        builder.use Faraday::FollowRedirects::Middleware
        builder.request :gzip
        builder.request :retry, { max: 2, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2 }

        builder.request :instrumentation
      end
      connection.get
    end

    def get(url, options = {})
      Oj.load(get_raw(url, options))
    end
    
    def get_html(url, options = {})
      Nokogiri::HTML(get_raw(url, options))
    end

    def get_xml(url, options = {})
      Ox.parse(get_raw(url, options))
    end

    def get_json(url)
      get(url, headers: { "Accept" => "application/json" })
    end
  end
end
