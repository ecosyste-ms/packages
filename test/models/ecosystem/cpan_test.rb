require "test_helper"

class CpanTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Metacpan.org', url: 'https://metacpan.org', ecosystem: 'cpan')
    @ecosystem = Ecosystem::Cpan.new(@registry.url)
    @package = Package.new(ecosystem: 'cpan', name: 'Dpkg')
    @version = @package.versions.build(number: '1.21.5')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://metacpan.org/dist/Dpkg'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version.number)
    assert_equal registry_url, 'https://metacpan.org/dist/Dpkg'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_nil download_url
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package.name)
    assert_nil documentation_url
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package.name, @version.number)
    assert_nil documentation_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_nil install_command
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_nil install_command
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://metacpan.org/dist/Dpkg"
  end

  test 'all_package_names' do
    stub_request(:get, "https://fastapi.metacpan.org/v1/release/_search?fields=distribution&q=status:latest&scroll=1m&size=5000")
      .to_return({ status: 200, body: file_fixture('cpan/_search?fields=distribution&q=status:latest&scroll=1m&size=5000') })
    stub_request(:get, "https://fastapi.metacpan.org/v1/_search/scroll?scroll=1m&scroll_id=cXVlcnlUaGVuRmV0Y2g7Mzs4ODgwOTU5OTpwRlJ6eDBNSFNKdW8tMGprOEZCMUdnOzUyMDI4Mzc1Nzg6LTY5R01xYVRRajZwWGIzZlA4Q2lxUTs1MjAyODM3NTc5Oi02OUdNcWFUUWo2cFhiM2ZQOENpcVE7MDs=")
      .to_return({ status: 200, body: file_fixture('cpan/scroll?scroll=1m&scroll_id=cXVlcnlUaGVuRmV0Y2g7Mzs4ODgwOTU5OTpwRlJ6eDBNSFNKdW8tMGprOEZCMUdnOzUyMDI4Mzc1Nzg6LTY5R01xYVRRajZwWGIzZlA4Q2lxUTs1MjAyODM3NTc5Oi02OUdNcWFUUWo2cFhiM2ZQOENpcVE7MDs=') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 4999
    assert_equal all_package_names.last, 'Acme-MakeMoneyAtHome'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://fastapi.metacpan.org/v1/release/_search?fields=distribution&q=status:latest&size=100&sort=date:desc")
      .to_return({ status: 200, body: file_fixture('cpan/_search?fields=distribution&q=status:latest&scroll=1m&size=5000') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 4999
    assert_equal recently_updated_package_names.last, 'Acme-MakeMoneyAtHome'
  end
  
  test 'package_metadata' do
    stub_request(:get, "https://fastapi.metacpan.org/v1/release/Dpkg")
      .to_return({ status: 200, body: file_fixture('cpan/Dpkg') })
    package_metadata = @ecosystem.package_metadata('Dpkg')

    assert_equal package_metadata, {
      :name=>"Dpkg", 
      :homepage=>"https://wiki.debian.org/Teams/Dpkg", 
      :description=>"Debian Package Manager Perl modules", 
      :licenses=>"gpl_2", 
      :repository_url=>"https://git.dpkg.org/cgit/dpkg/dpkg.git"
    }
  end

  test 'versions_metadata' do
    stub_request(:get, "https://fastapi.metacpan.org/v1/release/Dpkg")
      .to_return({ status: 200, body: file_fixture('cpan/Dpkg') })
    stub_request(:get, "https://fastapi.metacpan.org/v1/release/_search?fields=version,date&q=distribution:Dpkg&size=5000")
      .to_return({ status: 200, body: file_fixture('cpan/_search?fields=version,date&q=distribution:Dpkg&size=5000') })
      
    package_metadata = @ecosystem.package_metadata('Dpkg')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"v1.20.9", :published_at=>"2021-04-13T23:33:15"},
      {:number=>"v1.19.2", :published_at=>"2018-10-08T10:54:58"},
      {:number=>"v1.19.5", :published_at=>"2019-02-23T17:40:31"},
      {:number=>"v1.20.4", :published_at=>"2020-07-07T06:22:23"},
      {:number=>"v1.21.2", :published_at=>"2022-03-13T20:07:04"},
      {:number=>"v1.20.6", :published_at=>"2021-01-08T04:23:50"},
      {:number=>"v1.21.0", :published_at=>"2021-12-05T18:08:48"},
      {:number=>"v1.21.4", :published_at=>"2022-03-26T12:56:21"},
      {:number=>"v1.21.5", :published_at=>"2022-03-29T01:07:10"},
      {:number=>"v1.19.1", :published_at=>"2018-09-26T18:53:52"},
      {:number=>"v1.20.0", :published_at=>"2020-03-08T03:05:24"},
      {:number=>"v1.19.6", :published_at=>"2019-03-25T14:54:21"},
      {:number=>"v1.19.3", :published_at=>"2019-01-22T18:41:25"},
      {:number=>"v1.20.7", :published_at=>"2021-01-09T00:19:44"},
      {:number=>"v1.20.2", :published_at=>"2020-06-27T23:35:03"},
      {:number=>"v1.20.5", :published_at=>"2020-07-08T03:55:55"},
      {:number=>"v1.21.3", :published_at=>"2022-03-24T20:19:38"},
      {:number=>"v1.21.1", :published_at=>"2021-12-06T20:23:10"},
      {:number=>"v1.20.8", :published_at=>"2021-04-13T21:44:34"},
      {:number=>"v1.20.3", :published_at=>"2020-06-29T11:02:10"},
      {:number=>"v1.19.7", :published_at=>"2019-06-03T21:51:58"},
      {:number=>"v1.20.1", :published_at=>"2020-06-27T01:26:33"}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://fastapi.metacpan.org/v1/release/_search?q=distribution:Dpkg&size=5000")
      .to_return({ status: 200, body: file_fixture('cpan/_search?q=distribution:Dpkg&size=5000') })
    dependencies_metadata = @ecosystem.dependencies_metadata('Dpkg', 'v1.21.5', nil)
    
    assert_equal dependencies_metadata, [
      {:package_name=>"Test-More", :requirements=>"0", :kind=>"test", :ecosystem=>"cpan"},
      {:package_name=>"TAP-Harness", :requirements=>"0", :kind=>"test", :ecosystem=>"cpan"},
      {:package_name=>"Module-Build", :requirements=>"0.4004", :kind=>"configure", :ecosystem=>"cpan"},
      {:package_name=>"perl", :requirements=>"v5.28.1", :kind=>"runtime", :ecosystem=>"cpan"}
    ]
  end
end
