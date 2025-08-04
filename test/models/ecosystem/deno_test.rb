require "test_helper"

class DenoTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'deno.land', url: 'https://deno.land', ecosystem: 'deno')
    @ecosystem = Ecosystem::Deno.new(@registry)
    @package = Package.new(ecosystem: 'deno', name: 'deno_es')
    @version = @package.versions.build(number: 'v0.4.2')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, "https://deno.land/x/deno_es"
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, "https://deno.land/x/deno_es@v0.4.2"
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_nil download_url
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, 'https://doc.deno.land/https://deno.land/x/deno_es/mod.ts'
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_equal documentation_url, 'https://doc.deno.land/https://deno.land/x/deno_es@v0.4.2/mod.ts'
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
    assert_equal check_status_url,  "https://apiland.deno.dev/v2/modules/deno_es"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:deno/deno_es'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:deno/deno_es@v0.4.2'
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://apiland.deno.dev/v2/modules?page=1&limit=100")
      .to_return({ status: 200, body: file_fixture('deno/modules?page=1&limit=100') })
    stub_request(:get, "https://apiland.deno.dev/v2/modules?page=2&limit=100")
      .to_return({ status: 200, body: file_fixture('deno/modules?page=2&limit=100') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 100
    assert_equal all_package_names.last, 'xhr'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://apiland.deno.dev/v2/modules")
      .to_return({ status: 200, body: file_fixture('deno/modules') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 300
    assert_equal recently_updated_package_names.first, 'jose'
  end

  test 'package_metadata' do
    stub_request(:get, "https://apiland.deno.dev/v2/modules/deno_es")
      .to_return({ status: 200, body: file_fixture('deno/deno_es') })
    stub_request(:get, "https://cdn.deno.land/deno_es/meta/versions.json")
      .to_return({ status: 200, body: file_fixture('deno/versions.json') })
    stub_request(:get, "https://cdn.deno.land/deno_es/versions/v0.4.3/meta/meta.json")
      .to_return({ status: 200, body: file_fixture('deno/meta.json.2') })
    package_metadata = @ecosystem.package_metadata('deno_es')
    
    assert_equal package_metadata[:name], "deno_es"
    assert_equal package_metadata[:description], "deno elasticsearch"
    assert_nil package_metadata[:homepage]
    assert_nil package_metadata[:licenses]
    assert_equal package_metadata[:repository_url], "https://github.com/jiawei397/deno_es"
    assert_nil package_metadata[:keywords_array]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://apiland.deno.dev/v2/modules/deno_es")
      .to_return({ status: 200, body: file_fixture('deno/deno_es') })
    stub_request(:get, "https://cdn.deno.land/deno_es/meta/versions.json")
      .to_return({ status: 200, body: file_fixture('deno/versions.json') })
      stub_request(:get, "https://cdn.deno.land/deno_es/versions/v0.4.3/meta/meta.json")
      .to_return({ status: 200, body: file_fixture('deno/meta.json.2') })
    stub_request(:get, "https://cdn.deno.land/deno_es/versions/v0.4.2/meta/meta.json")
      .to_return({ status: 200, body: file_fixture('deno/meta.json') })
    stub_request(:get, "https://cdn.deno.land/deno_es/versions/v0.4.1/meta/meta.json")
      .to_return({ status: 200, body: file_fixture('deno/meta.json.1') })
    package_metadata = @ecosystem.package_metadata('deno_es')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"v0.4.3", :published_at=>"2022-05-07T07:05:25.556Z"},
      {:number=>"v0.4.2", :published_at=>"2022-03-25T06:16:54.883Z"},
      {:number=>"v0.4.1", :published_at=>"2022-01-18T05:37:36.728Z"}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://cdn.deno.land/deno_es/versions/v0.4.2/meta/deps_v2.json")
      .to_return({ status: 200, body: file_fixture('deno/deps_v2.json') })
    dependencies_metadata = @ecosystem.dependencies_metadata('deno_es', 'v0.4.2', {})

    assert_equal dependencies_metadata, [
      {:package_name=>"jw_fetch", :requirements=>"v0.2.5", :kind=>"runtime", :ecosystem=>"deno"},
      {:package_name=>"deno_es", :requirements=>"v0.4.2", :kind=>"runtime", :ecosystem=>"deno"},
      {:package_name=>"deno_mock", :requirements=>"v2.0.0", :kind=>"runtime", :ecosystem=>"deno"}
    ]
  end
end
