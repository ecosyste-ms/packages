require "test_helper"

class OpmTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'opm.openresty.org', url: 'https://opm.openresty.org', ecosystem: 'opm')
    @ecosystem = Ecosystem::Opm.new(@registry)
    @package = Package.new(ecosystem: @registry.ecosystem, name: 'openresty/lua-resty-core', metadata: { 'dependencies' => ['openresty/lua-resty-lrucache >= 0.08'] })
    @version = @package.versions.build(number: '0.1.15')
  end

  test 'registry_url' do
    assert_equal 'https://opm.openresty.org/package/openresty/lua-resty-core/', @ecosystem.registry_url(@package)
  end

  test 'registry_url with version' do
    assert_equal 'https://opm.openresty.org/package/openresty/lua-resty-core/?version=0.1.15', @ecosystem.registry_url(@package, @version.number)
  end

  test 'download_url' do
    assert_equal 'https://opm.openresty.org/download/openresty/lua-resty-core-0.1.15.tar.gz', @ecosystem.download_url(@package, @version.number)
  end

  test 'documentation_url' do
    assert_equal 'https://opm.openresty.org/package/openresty/lua-resty-core/', @ecosystem.documentation_url(@package)
  end

  test 'install_command' do
    assert_equal 'opm get openresty/lua-resty-core', @ecosystem.install_command(@package)
  end

  test 'install_command with version' do
    assert_equal 'opm get openresty/lua-resty-core 0.1.15', @ecosystem.install_command(@package, @version.number)
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal 'pkg:opm/openresty/lua-resty-core', purl
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, 'https://opm.openresty.org/packages')
      .to_return({ status: 200, body: opm_packages_html })

    assert_equal ['openresty/lua-resty-core', 'agentzh/lua-resty-cookie'], @ecosystem.all_package_names
  end

  test 'recently_updated_package_names' do
    stub_request(:get, 'https://opm.openresty.org/packages')
      .to_return({ status: 200, body: opm_packages_html })

    assert_equal ['openresty/lua-resty-core', 'agentzh/lua-resty-cookie'], @ecosystem.recently_updated_package_names
  end

  test 'package_metadata' do
    stub_request(:get, 'https://opm.openresty.org/package/openresty/lua-resty-core/')
      .to_return({ status: 200, body: opm_package_html })

    metadata = @ecosystem.package_metadata('openresty/lua-resty-core')

    assert_equal 'openresty/lua-resty-core', metadata[:name]
    assert_equal 'New FFI-based Lua API for the ngx_lua module', metadata[:description]
    assert_equal 'https://opm.openresty.org/package/openresty/lua-resty-core/', metadata[:homepage]
    assert_equal 'https://github.com/openresty/lua-resty-core', metadata[:repository_url]
    assert_equal 'This module is licensed under the BSD license.', metadata[:licenses]
    assert_equal ['0.1.15', '0.1.14'], metadata[:versions]
    assert_equal ['openresty/lua-resty-lrucache >= 0.08'], metadata[:metadata]['dependencies']
  end

  test 'versions_metadata' do
    stub_request(:get, 'https://opm.openresty.org/package/openresty/lua-resty-core/')
      .to_return({ status: 200, body: opm_package_html })

    metadata = @ecosystem.package_metadata('openresty/lua-resty-core')
    versions = @ecosystem.versions_metadata(metadata, ['0.1.14'])

    assert_equal 1, versions.length
    assert_equal '0.1.15', versions.first[:number]
  end

  test 'dependencies_metadata' do
    deps = @ecosystem.dependencies_metadata(@package.name, @version.number, @package)

    assert_equal [
      { package_name: 'openresty/lua-resty-lrucache', requirements: '>= 0.08', kind: 'runtime', ecosystem: 'opm' }
    ], deps
  end

  private

  def opm_packages_html
    <<~HTML
      <ul class="package_list">
        <li><a class="title" href="/package/openresty/lua-resty-core/">openresty/lua-resty-core</a></li>
        <li><a class="title" href="/package/agentzh/lua-resty-cookie/">agentzh/lua-resty-cookie</a></li>
      </ul>
    HTML
  end

  def opm_package_html
    <<~HTML
      <div class="main_col package_page">
        <h2>lua-resty-core</h2>
        <div class="description"><p>New FFI-based Lua API for the ngx_lua module</p></div>
        <div class="metadata_columns">
          <div class="column"><h3>Account</h3>openresty</div>
          <div class="column"><h3>Repo</h3><a href="https://github.com/openresty/lua-resty-core">repo</a></div>
        </div>
        <h3>Dependencies</h3>
        <div class="description"><p>openresty/lua-resty-lrucache >= 0.08</p></div>
        <h3>Versions</h3>
        <ul class="package_list">
          <li class="package_row"><span class="version_name">0.1.15</span></li>
          <li class="package_row"><span class="version_name">0.1.14</span></li>
        </ul>
        <h1>Copyright and License</h1>
        <p>This module is licensed under the BSD license.</p>
      </div>
    HTML
  end
end
