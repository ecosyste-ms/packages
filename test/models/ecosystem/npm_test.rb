require "test_helper"

class NpmTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    @ecosystem = Ecosystem::Npm.new(@registry)
    @package = Package.new(ecosystem: 'npm', name: 'base62')
    @version = @package.versions.build(number: '2.0.1')
    @maintainer = @registry.maintainers.build(login: 'foo')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://www.npmjs.com/package/base62'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://www.npmjs.com/package/base62/v/2.0.1'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://registry.npmjs.org/base62/-/base62-2.0.1.tgz"
  end

  test 'download_url for namespaced packages' do
    @package.name = '@digital-boss/n8n-nodes-mollie'
    download_url = @ecosystem.download_url(@package, '0.2.0')
    assert_equal download_url, "https://registry.npmjs.org/@digital-boss/n8n-nodes-mollie/-/n8n-nodes-mollie-0.2.0.tgz"
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
    assert_equal install_command, 'npm install base62'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'npm install base62@2.0.1'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://registry.npmjs.org/base62"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:npm/base62'
    assert PackageURL.parse(purl)
  end

  test 'purl with namespace' do
    @package = Package.new(ecosystem: 'npm', name: '@fudge-ai/browser', namespace: 'fudge-ai')
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:npm/%40fudge-ai/browser'
    assert PackageURL.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:npm/base62@2.0.1'
    assert PackageURL.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://raw.githubusercontent.com/nice-registry/all-the-package-names/master/names.json")
      .to_return({ status: 200, body: file_fixture('npm/names.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 290
    assert_equal all_package_names.last, '03-creatfront'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://npm.ecosyste.ms/recent")
      .to_return({ status: 200, body: file_fixture('npm/recent') })
    stub_request(:get, "https://registry.npmjs.org/-/rss?descending=true&limit=50")
      .to_return({ status: 200, body: file_fixture('npm/new-rss') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 250
    assert_equal recently_updated_package_names.last, 'test-raydium-sdk-v2'
  end

  test 'package_metadata' do
    stub_request(:get, "https://registry.npmjs.org/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62') })
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62.1') })
    package_metadata = @ecosystem.package_metadata('base62')

    assert_equal package_metadata[:name], "base62"
    assert_equal package_metadata[:description], "JavaScript Base62 encode/decoder"
    assert_equal package_metadata[:homepage], "https://github.com/base62/base62.js"
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal package_metadata[:repository_url], "https://github.com/base62/base62.js"
    assert_equal package_metadata[:keywords_array], ["base-62", "encoder", "decoder"]
    assert_equal package_metadata[:downloads], 1076972
    assert_equal package_metadata[:downloads_period], "last-month"
    assert_nil package_metadata[:namespace]
    assert_equal package_metadata[:metadata], {"funding"=>nil, "dist-tags"=>{"latest"=>"2.0.1"}, "_npmUser"=>{"name"=>"fnd", "email"=>"fndnpm@burningchrome.com"}, "dist"=>{"integrity"=>"sha512-4t4WQK7mdbcWzqEBiq6tfo2qDCeIZGXvjifJZyxHIVcjQkZJxpFtu/pa2Va69OouCkg6izZ08hKnPxroeDyzew==", "shasum"=>"729cfe179ed34c61e4a489490105b44ce4ea1197", "tarball"=>"https://registry.npmjs.org/base62/-/base62-2.0.1.tgz", "fileCount"=>26, "unpackedSize"=>30256, "npm-signature"=>"-----BEGIN PGP SIGNATURE-----\r\nVersion: OpenPGP.js v3.0.4\r\nComment: https://openpgpjs.org\r\n\r\nwsFcBAEBCAAQBQJcf+IACRA9TVsSAnZWagAAYcgP/R9re5nH8L1WU2+7NvFi\nmQtIIzIUooy+c5bOuhiioLz76XVH1RenZYNE2yDRlenDYIxmZk7lRBjiYd7g\nUMW1EEOvpiq/2hNquyY20Ol6/maHTXWP6f10iGFP7VmgQ+JvBIibQr1I1XoO\naWXaVjTXZ4VVZoqY77/xgU1dRig1B24NdDXQR2mU4u6dg2Ch9RjbmGhOmFSD\nNqrd3hhvcuPnMRStIUo9KuXc6AdysGkqXHoJF3rbRL3/t8OMJ86P0oM0/gdU\nH6r8tXIzpxPnn/g5KJF+41q/lqzEzdv+8E92wakeCd1gTBaaZvjmsNADl5sL\nIPq6m5OZeF9RVrcObFBHcIE+GyPimS3OZ5pslg1+Fw0nQfl+NeA3j2fO95jT\ne7zTdT9fmxAgej+cw2eOSw1f0LfhwPk27Ab1vpuTQq/cxkuS6jBUOhVH9scv\n15x97TpcvX81RECbVsdFH18BgSYBYTH9o6lx5f9vvJPksdLLhMCtxKi3ZCqW\niz35af53A34n7dT1ax49KF5cvEiFyBvlDKx9+e5KA+GuczQ0VsDK4OtlWJtW\nNfS34EwLgEgLVK8Qm0kEVJdqms8AfQhYon9TDyi16wKcYFrcCBFUl4ARav0d\n8d0Qna8kDF4nweAzgg1jURxJDsRUy5Af29OH3D2u+dDeKgrKi33GzNi2Zn5p\nz7Av\r\n=Zd+c\r\n-----END PGP SIGNATURE-----\r\n"}, "gitHead"=>"f99208bff69de2d8d11acfc9b1332d572fe2f4dd", "main"=>"./lib/legacy.js", "scripts"=>{"test"=>"mocha", "benchmark"=>"node benchmark/benchmarks.js; echo; node benchmark/benchmarks_legacy.js"}, "_npmVersion"=>"6.7.0", "_nodeVersion"=>"11.10.1", "_hasShrinkwrap"=>false, "directories"=>{}}
  end

  test 'versions_metadata' do
    stub_request(:get, "https://registry.npmjs.org/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62') })
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62.1') })
    package_metadata = @ecosystem.package_metadata('base62')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [      
      {:number=>"0.1.0", :published_at=>"2012-02-24T18:04:06.916Z", :licenses=>"", :integrity=>"sha1-03b8bde71477f095dff3455ccd5f8e0fd6bf91fa", :metadata=>{:deprecated=>nil}},
      {:number=>"0.1.1", :published_at=>"2012-12-09T05:11:27.662Z", :licenses=>"", :integrity=>"sha1-7b4174c2f94449753b11c2651c083da841a7b084", :metadata=>{:deprecated=>nil}},
      {:number=>"0.1.2", :published_at=>"2014-07-15T21:24:45.597Z", :licenses=>"", :integrity=>"sha1-6f0d1b71d7cbc18234fa6f86928c08d3923f547b", :metadata=>{:deprecated=>nil}},
      {:number=>"1.0.0", :published_at=>"2014-10-11T07:22:23.512Z", :licenses=>"MIT", :integrity=>"sha1-47e25e40e841597877807a3a459a6b1f3f8a88a1", :metadata=>{:deprecated=>nil}},
      {:number=>"1.1.0", :published_at=>"2015-02-23T09:52:54.646Z", :licenses=>"MIT", :integrity=>"sha1-4659de866558906d43fec61e07abd4397da74c19", :metadata=>{:deprecated=>nil}},
      {:number=>"1.1.1", :published_at=>"2016-04-14T21:55:22.812Z", :licenses=>"MIT", :integrity=>"sha1-974e82c11bd5e00816b508a7ed9c7b9086c9db6b", :metadata=>{:deprecated=>nil}},
      {:number=>"1.1.2", :published_at=>"2016-11-14T00:43:51.131Z", :licenses=>"MIT", :integrity=>"sha1-22ced6a49913565bc0b8d9a11563a465c084124c", :metadata=>{:deprecated=>nil}},
      {:number=>"1.2.0", :published_at=>"2017-05-15T11:26:01.056Z", :licenses=>"MIT", :integrity=>"sha1-31e7e560dc846c9f44c1a531df6514da35474157", :metadata=>{:deprecated=>nil}},
      {:number=>"1.2.1", :published_at=>"2017-11-14T08:38:56.587Z", :licenses=>"MIT", :integrity=>"sha512-xVtfFHNPUzpCNHygpXFGMlDk3saxXLQcOOQzAAk6ibvlAHgT6WKXLv9rMFhcyEK1n9LuDmp/LxyGW/Fm9L8++g==", :metadata=>{:deprecated=>nil}},
      {:number=>"1.2.4", :published_at=>"2018-02-10T21:54:23.964Z", :licenses=>"MIT", :integrity=>"sha512-O4pCb20Z0YXcVWCQbna/q6P9Dq86OOCfXRveyL7ECiKKvProrPUIt4aXG6SUzdsbJa69WGKKzFEotTLaum7nbg==", :metadata=>{:deprecated=>nil}},
      {:number=>"1.2.5", :published_at=>"2018-02-10T23:16:39.461Z", :licenses=>"MIT", :integrity=>"sha512-Dq8/KtIxvQmU0Wml7DFNx/04f0g3wtFaKmUwhDjdKUSuHkftP4PWZo5WdWpVgIPjZsfZwtDGQ24m52koq8dtjA==", :metadata=>{:deprecated=>nil}},
      {:number=>"1.2.6", :published_at=>"2018-02-14T12:24:12.680Z", :licenses=>"MIT", :integrity=>"sha512-HxRh87vRHaLnPkeNMsj3x4qbil8Hm0sG6h2PCeDOT0+5cmEX59z1Eu9WyzE9dOplH91QQl09Ram/f+cygm8mSA==", :metadata=>{:deprecated=>nil}},
      {:number=>"1.2.7", :published_at=>"2018-02-14T12:46:17.280Z", :licenses=>"MIT", :integrity=>"sha512-ck0nDbXLEq2nD5jIcEzdpk07sYQ5P6z4NMTIgeQCFr5CCRZzmgUPlOes4o0k5pvEUQJnKO/D079ybzjpjIKf2Q==", :metadata=>{:deprecated=>nil}},
      {:number=>"1.2.8", :published_at=>"2018-03-30T17:15:14.729Z", :licenses=>"MIT", :integrity=>"sha512-V6YHUbjLxN1ymqNLb1DPHoU1CpfdL7d2YTIp5W3U4hhoG4hhxNmsFDs66M9EXxBiSEke5Bt5dwdfMwwZF70iLA==", :metadata=>{:deprecated=>nil}},
      {:number=>"2.0.0", :published_at=>"2018-04-13T09:18:23.449Z", :licenses=>"MIT", :integrity=>"sha512-s3DXUcvJVW9vd9L/iahft3cxsrBQsXfG0ktX/uzkKOO7ZHHE8Lw3mP+rSXb7YzVavX+fB1jX1GFHDfI/NX8/SQ==", :metadata=>{:deprecated=>nil}},
      {:number=>"2.0.1", :published_at=>"2019-03-06T15:06:40.387Z", :licenses=>"MIT", :integrity=>"sha512-4t4WQK7mdbcWzqEBiq6tfo2qDCeIZGXvjifJZyxHIVcjQkZJxpFtu/pa2Va69OouCkg6izZ08hKnPxroeDyzew==", :metadata=>{:deprecated=>nil}},
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://registry.npmjs.org/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62') })
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62.1') })
    package_metadata = @ecosystem.package_metadata('base62')
    dependencies_metadata = @ecosystem.dependencies_metadata('base62', '2.0.0', package_metadata)

    assert_equal dependencies_metadata, [
      {:package_name=>"mocha", :requirements=>"~5.1.0", :kind=>"Development", :optional=>false, :ecosystem=>"npm"}
    ]
  end

  test 'maintainer_url' do 
    assert_equal @ecosystem.maintainer_url(@maintainer), 'https://www.npmjs.com/~foo'
  end
end
