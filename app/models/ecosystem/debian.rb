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

    def documentation_url(package, version = nil)
      "https://packages.debian.org/#{registry_codename}/#{package.name}"
    end
  end
end
