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

    def check_status_url(package)
      package_url(package)
    end

    def ecosystem_name(ecosystem)
      find(ecosystem).try(:formatted_name) || ecosystem
    end

    def dependencies_metadata(_name, _version, _package)
      []
    end

    def package_metadata(name)
      map_package_metadata(fetch_package_metadata(name))
    end

    def map_dependencies(deps, kind, optional = false, ecosystem = self.class.name.demodulize)
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
          ecosystem: self.class.name.demodulize,
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
