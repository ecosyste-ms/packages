require "test_helper"

class PuppetTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'forge.puppet.com', url: 'https://forge.puppet.com', ecosystem: 'puppet')
    @ecosystem = Ecosystem::Puppet.new(@registry.url)
    @package = Package.new(ecosystem: 'puppet', name: 'puppet-fail2ban')
    @version = @package.versions.build(number: '4.1.0')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://forge.puppet.com/puppet/fail2ban'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version.number)
    assert_equal registry_url, 'https://forge.puppet.com/puppet/fail2ban/4.1.0'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://forge.puppet.com/v3/files/puppet-fail2ban-4.1.0.tar.gz"
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_nil documentation_url
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_nil documentation_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)

    assert_equal install_command, 'puppet module install puppet-fail2ban'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'puppet module install puppet-fail2ban --version 4.1.0'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://forge.puppet.com/puppet/fail2ban"
  end

  test 'all_package_names' do
    stub_request(:get, "https://forgeapi-cdn.puppet.com/v3/modules?limit=100&offset=0")
      .to_return({ status: 200, body: file_fixture('puppet/modules?limit=100&offset=0') })
    stub_request(:get, "https://forgeapi-cdn.puppet.com/v3/modules?limit=100&offset=100")
      .to_return({ status: 200, body: file_fixture('puppet/modules?limit=100&offset=100') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 100
    assert_equal all_package_names.last, 'ghoneycutt-ssh'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://forgeapi-cdn.puppet.com/v3/modules?limit=100&sort_by=latest_release")
      .to_return({ status: 200, body: file_fixture('puppet/modules?limit=100&sort_by=latest_release') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 100
    assert_equal recently_updated_package_names.last, 'deric-pgprobackup'
  end

  test 'package_metadata' do
    stub_request(:get, "https://forgeapi-cdn.puppet.com/v3/modules/puppet-fail2ban")
      .to_return({ status: 200, body: file_fixture('puppet/puppet-fail2ban') })
    package_metadata = @ecosystem.package_metadata('puppet-fail2ban')
    
    assert_equal package_metadata[:name], "puppet-fail2ban"
    assert_equal package_metadata[:description], "This module installs, configures and manages the Fail2ban service."
    assert_equal package_metadata[:homepage], "https://github.com/voxpupuli/puppet-fail2ban"
    assert_equal package_metadata[:licenses], "Apache-2.0"
    assert_equal package_metadata[:repository_url], "https://github.com/voxpupuli/puppet-fail2ban.git"
    assert_equal package_metadata[:keywords_array], ["iptables", "fail2ban", "firewall", "firewalling"]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://forgeapi-cdn.puppet.com/v3/modules/puppet-fail2ban")
      .to_return({ status: 200, body: file_fixture('puppet/puppet-fail2ban') })
    stub_request(:get, "https://forgeapi-cdn.puppet.com/v3/releases/puppet-fail2ban-4.1.0")
      .to_return({ status: 200, body: file_fixture('puppet/puppet-fail2ban-4.1.0') })
    stub_request(:get, "https://forgeapi-cdn.puppet.com/v3/releases/puppet-fail2ban-4.0.0")
      .to_return({ status: 200, body: file_fixture('puppet/puppet-fail2ban-4.0.0') })
    package_metadata = @ecosystem.package_metadata('puppet-fail2ban')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"4.1.0", :published_at=>"2022-04-11 23:14:42 -0700", :integrity=>"sha256-ef58252f5398aeee9c332c99e16ffb75244b2a5a0bf42ca1f0d8f34e06a3a8ee"},
      {:number=>"4.0.0", :published_at=>"2021-12-13 14:43:26 -0800", :integrity=>"sha256-e1a249468eb4130d3e02afe761084a973048e6f804e93dcf0def27ac8a8efe38"}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://forgeapi-cdn.puppet.com/v3/modules/puppet-fail2ban")
      .to_return({ status: 200, body: file_fixture('puppet/puppet-fail2ban') })
    stub_request(:get, "https://forgeapi-cdn.puppet.com/v3/releases/puppet-fail2ban-4.1.0")
      .to_return({ status: 200, body: file_fixture('puppet/puppet-fail2ban-4.1.0') })
    package_metadata = @ecosystem.package_metadata('puppet-fail2ban')
    dependencies_metadata = @ecosystem.dependencies_metadata('puppet-fail2ban', '4.1.0', package_metadata)

    assert_equal dependencies_metadata, [
      {:package_name=>"puppet-extlib", :requirements=>">= 3.0.0 < 7.0.0", :kind=>"runtime", :ecosystem=>"puppet"},
      {:package_name=>"puppetlabs-stdlib", :requirements=>">= 4.25.0 < 9.0.0", :kind=>"runtime", :ecosystem=>"puppet"}
    ]
  end
end
