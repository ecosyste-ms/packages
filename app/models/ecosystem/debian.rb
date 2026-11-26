# frozen_string_literal: true
module Ecosystem
  class Debian < Deb
    def default_mirror_url
      "http://deb.debian.org/debian"
    end

    def components
      ['main', 'contrib', 'non-free', 'non-free-firmware']
    end

    # Releases before bullseye published security updates as <codename>/updates on the archive's own security mirror
    LEGACY_SECURITY_LAYOUT = %w[buster stretch jessie wheezy squeeze].freeze

    def default_security_mirror_url
      mirror_url.include?('archive.debian.org') ? 'http://archive.debian.org/debian-security' : 'http://security.debian.org/debian-security'
    end

    def security_suite_name
      return super if @registry.metadata['security_suite'].present? || @registry.metadata[:security_suite].present?

      LEGACY_SECURITY_LAYOUT.include?(registry_codename) ? "#{registry_codename}/updates" : super
    end

    def purl_namespace
      'debian'
    end

    def distro_qualifier
      "debian-#{@registry.version}"
    end

    def registry_url(package, version = nil)
      url = "https://tracker.debian.org/pkg/#{package.name}"
      url
    end

    # sources.debian.org has the unpacked source of every version in the archive, so try it before salsa
    def packaging_file_urls(package, version, path)
      component = package.metadata.to_h['component'].presence || 'main'
      prefix = package_pool_prefix(package.name)
      sources_url = "https://sources.debian.org/data/#{component}/#{prefix}/#{ERB::Util.url_encode(package.name)}/#{ERB::Util.url_encode(version)}/#{path}"
      [sources_url] + super
    end

    def documentation_url(package, version = nil)
      "https://packages.debian.org/#{registry_codename}/#{package.name}"
    end
  end
end
