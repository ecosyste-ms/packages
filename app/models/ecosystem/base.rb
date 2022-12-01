# frozen_string_literal: true

module Ecosystem
  class Base
    attr_accessor :registry
    attr_accessor :registry_url

    def initialize(registry)
      @registry = registry
      @registry_url = registry.url
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

    def registry_url(_package, _version = nil)
      nil
    end

    def download_url(_package, _version = nil)
      nil
    end

    def documentation_url(_package, _version = nil)
      nil
    end

    def install_command(_package, _version = nil)
      nil
    end

    def check_status_url(package)
      registry_url(package)
    end

    def check_status(package)
      url = check_status_url(package)
      response = Typhoeus.head(url, followlocation: true)
      "removed" if [400, 404, 410].include?(response.response_code)
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

    def map_dependencies(deps, kind, optional = false, ecosystem = self.class.name.demodulize.downcase)
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
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end

    def repo_fallback(repo, homepage)
      repo = "" if repo.nil?
      homepage = "" if homepage.nil?
      repo_url = UrlParser.try_all(repo) rescue ""
      homepage_url = UrlParser.try_all(homepage) rescue ""
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

    def maintainers_metadata(name)
      []
    end

    private

    def get_raw(url, options = {})
      resp = request(url, options)
      return nil unless resp.success?
      resp.body
    end

    def request(url, options = {})
      connection = Faraday.new url.strip, options do |builder|
        builder.use Faraday::FollowRedirects::Middleware
        builder.request :gzip
        builder.request :retry, { max: 5, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2 }

        builder.request :instrumentation
        builder.adapter  Faraday.default_adapter
      end
      connection.get
    end

    def get(url, options = {})
      resp = get_raw(url, options)
      return nil unless resp
      Oj.load(resp)
    end
    
    def get_html(url, options = {})
      resp = get_raw(url, options)
      return nil unless resp
      Nokogiri::HTML(resp)
    end

    def get_xml(url, options = {})
      resp = get_raw(url, options)
      return nil unless resp
      Nokogiri::XML(resp)
    end

    def get_json(url, options = {})
      options.deep_merge!(headers: { "Accept" => "application/json" })
      get(url, options)
    end
  end
end
