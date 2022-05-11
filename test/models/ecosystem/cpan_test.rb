require "test_helper"

class CpanTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Metacpan.org', url: 'https://metacpan.org', ecosystem: 'cpan')
    @ecosystem = Ecosystem::Cpan.new(@registry.url)
    @package = Package.new(ecosystem: 'cpan', name: 'Dpkg', metadata: {author: 'GUILLEM'})
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
    download_url = @ecosystem.download_url(@package, @version.number)
    assert_equal download_url, "https://cpan.metacpan.org/authors/id/G/GU/GUILLEM/Dpkg-1.21.5.tar.gz"
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
      :repository_url=>"https://git.dpkg.org/cgit/dpkg/dpkg.git",
      :metadata=>{
        :author=>"GUILLEM"
      }
    }
  end

  test 'versions_metadata' do
    stub_request(:get, "https://fastapi.metacpan.org/v1/release/Dpkg")
      .to_return({ status: 200, body: file_fixture('cpan/Dpkg') })
    stub_request(:get, "https://fastapi.metacpan.org/v1/release/_search?q=distribution:Dpkg&size=5000")
      .to_return({ status: 200, body: file_fixture('cpan/_search?q=distribution:Dpkg&size=5000') })
      
    package_metadata = @ecosystem.package_metadata('Dpkg')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"v1.20.9", :published_at=>"2021-04-13T23:33:15", :integrity=>"sha256-61155c6ff2c0efa8c9912dd7578aeacebc640591a710f8c993f7531053d76d87"},
      {:number=>"v1.19.2", :published_at=>"2018-10-08T10:54:58", :integrity=>"sha256-a32f62173f072ae84b35e0e912678105b52829b11ead9d51ea1fd7f9f28a5e47"},
      {:number=>"v1.19.5", :published_at=>"2019-02-23T17:40:31", :integrity=>"sha256-cdb266704f0233f545d15cce64245a38684cf68c7e17643ff2ef3bc9f4b225ef"},
      {:number=>"v1.20.4", :published_at=>"2020-07-07T06:22:23", :integrity=>"sha256-6b273c48d4d7dcb1266b1f12a3b3c7d7ec0de5d13ee70bf74e17e173a97e1f67"},
      {:number=>"v1.21.2", :published_at=>"2022-03-13T20:07:04", :integrity=>"sha256-cd92c3f6f7fcf73833966ecd4fd730325bc76d7f1cbf1c3d49899e2d92f7e3f7"},
      {:number=>"v1.20.6", :published_at=>"2021-01-08T04:23:50", :integrity=>"sha256-2e709129e9249fb223da09a8156b954edb43eae27cc5dcdabee354f241fa3d9d"},
      {:number=>"v1.21.0", :published_at=>"2021-12-05T18:08:48", :integrity=>"sha256-1871df79691d41f5cc8351e6cec8c8fe33b8bef9b5730dcbbbf64f1ef4827f75"},
      {:number=>"v1.21.4", :published_at=>"2022-03-26T12:56:21", :integrity=>"sha256-4894e5bdee2080f0a0c80e66ee9ad3d87201e526d4c22263cc900366e1701bfd"},
      {:number=>"v1.21.5", :published_at=>"2022-03-29T01:07:10", :integrity=>"sha256-8464844c1d045adf1ee44409762b200f3197ed8609195f230170bfa116525a7e"},
      {:number=>"v1.20.3", :published_at=>"2020-06-29T11:02:10", :integrity=>"sha256-ce1ac0ae78bffbcccd9123d42b39e3ab40607ab525bd0b1d5e5aebe29957c895"},
      {:number=>"v1.19.7", :published_at=>"2019-06-03T21:51:58", :integrity=>"sha256-e56d3f7f275e259dbb484a9affa723808a23ed77bf1512bdb5bad9bfaa73bfa5"},
      {:number=>"v1.20.8", :published_at=>"2021-04-13T21:44:34", :integrity=>"sha256-60d271e95d50d4eedf757d43a6a69d4d5f1c48354fb3249202236ac2466eee0b"},
      {:number=>"v1.20.1", :published_at=>"2020-06-27T01:26:33", :integrity=>"sha256-d8e3e5fdbffc0be9b89a1c631b2d72bb67f3e97b10c7a649911be7badb3107b5"},
      {:number=>"v1.20.7", :published_at=>"2021-01-09T00:19:44", :integrity=>"sha256-872ce8f578a960dd6b0055f6f5cb7bc5dc6880120635ea37a0d56ab730750fa6"},
      {:number=>"v1.19.1", :published_at=>"2018-09-26T18:53:52", :integrity=>"sha256-eac34dfff280bba06e8b8a738b84e4b9ef69f189de6089e7c7a2e4d083f0d6ba"},
      {:number=>"v1.20.0", :published_at=>"2020-03-08T03:05:24", :integrity=>"sha256-d6518999098a6ae63f864c722504defbda2348781d543b22d26796ea5d85f6ee"},
      {:number=>"v1.19.6", :published_at=>"2019-03-25T14:54:21", :integrity=>"sha256-2fc1046d3d5edcbab94980755db675361d85a21e65befffa0b64ed580508ffe2"},
      {:number=>"v1.19.3", :published_at=>"2019-01-22T18:41:25", :integrity=>"sha256-2c1f7e924c5a25a1bc1859189f8c80d090beb268a3780e7bfdbcfc7d104beb29"},
      {:number=>"v1.20.2", :published_at=>"2020-06-27T23:35:03", :integrity=>"sha256-8fc5bfac516c7a621a266a53f942a5e99ca717f4c4cefab258b4daac6a9ee99e"},
      {:number=>"v1.20.5", :published_at=>"2020-07-08T03:55:55", :integrity=>"sha256-a46d6c13f2d3c1b1f1d4ed6d6378aad7dcf3f37f7d7ca4d6a3feb764f84e9dfc"},
      {:number=>"v1.21.1", :published_at=>"2021-12-06T20:23:10", :integrity=>"sha256-df4e5c7a72fb42c106b3bb1e5142a09db4327246be72d867daa42b6a14be0e2b"},
      {:number=>"v1.21.3", :published_at=>"2022-03-24T20:19:38", :integrity=>"sha256-af92e5f64b5c26eafff82baf1ad5f5c9ad10a56fb58c3b5bfca5344360a9c642"}
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
