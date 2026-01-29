# frozen_string_literal: true
module Ecosystem
  class Ubuntu < Deb
    def default_mirror_url
      "http://archive.ubuntu.com/ubuntu"
    end

    def components
      ['main', 'universe', 'multiverse', 'restricted']
    end

    def purl_namespace
      'ubuntu'
    end

    def distro_qualifier
      "ubuntu-#{@registry.version}"
    end

    def registry_url(package, version = nil)
      url = "https://launchpad.net/ubuntu/+source/#{package.name}"
      url += "/#{version.number}" if version.present?
      url
    end
  end
end
