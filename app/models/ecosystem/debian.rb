# frozen_string_literal: true
module Ecosystem
  class Debian < Deb
    def default_mirror_url
      "http://deb.debian.org/debian"
    end

    def components
      ['main', 'contrib', 'non-free', 'non-free-firmware']
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
