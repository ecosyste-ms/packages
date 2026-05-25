require "test_helper"

class WordpressTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'wordpress.org/plugins', url: 'https://wordpress.org/plugins', ecosystem: 'wordpress')
    @ecosystem = Ecosystem::Wordpress.new(@registry)
    @package = Package.new(ecosystem: @registry.ecosystem, name: 'akismet')
    @version = @package.versions.build(number: '5.5')
  end

  test 'registry_url' do
    assert_equal 'https://wordpress.org/plugins/akismet/', @ecosystem.registry_url(@package)
  end

  test 'registry_url with version' do
    assert_equal 'https://wordpress.org/plugins/akismet/', @ecosystem.registry_url(@package, @version)
  end

  test 'documentation_url' do
    assert_equal 'https://wordpress.org/plugins/akismet/', @ecosystem.documentation_url(@package)
  end

  test 'install_command' do
    assert_equal 'wp plugin install akismet', @ecosystem.install_command(@package)
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal 'pkg:wordpress/akismet', purl
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, %r{https://api.wordpress.org/plugins/info/1.2/\?.*action=query_plugins.*})
      .to_return({ status: 200, body: wordpress_query_response })

    assert_equal ['akismet', 'classic-editor'], @ecosystem.all_package_names
  end

  test 'recently_updated_package_names' do
    stub_request(:get, %r{https://api.wordpress.org/plugins/info/1.2/\?.*action=query_plugins.*request%5Bbrowse%5D=updated.*})
      .to_return({ status: 200, body: wordpress_query_response })

    assert_equal ['akismet', 'classic-editor'], @ecosystem.recently_updated_package_names
  end

  test 'package_metadata' do
    stub_wordpress_plugin_information

    metadata = @ecosystem.package_metadata('akismet')

    assert_equal 'akismet', metadata[:name]
    assert_equal 'Spam protection for WordPress.', metadata[:description]
    assert_equal 'https://akismet.com/', metadata[:homepage]
    assert_equal 'https://akismet.com/', metadata[:repository_url]
    assert_equal ['spam', 'security'], metadata[:keywords_array]
    assert_equal 'Unknown', metadata[:licenses]
    assert_equal 123456, metadata[:downloads]
    assert_equal 'total', metadata[:downloads_period]
    assert_equal ['5.5', '5.4'], metadata[:versions]
    assert_equal 'Automattic', metadata[:metadata]['author']
  end

  test 'download_url' do
    stub_wordpress_plugin_information

    assert_equal 'https://downloads.wordpress.org/plugin/akismet.5.5.zip', @ecosystem.download_url(@package)
    assert_equal 'https://downloads.wordpress.org/plugin/akismet.5.5.zip', @ecosystem.download_url(@package, '5.5')
  end

  test 'versions_metadata' do
    stub_wordpress_plugin_information

    metadata = @ecosystem.package_metadata('akismet')
    versions = @ecosystem.versions_metadata(metadata, ['5.4'])

    assert_equal 1, versions.length
    assert_equal '5.5', versions.first[:number]
    assert_equal 'Unknown', versions.first[:licenses]
  end

  private

  def stub_wordpress_plugin_information
    stub_request(:get, %r{https://api.wordpress.org/plugins/info/1.2/\?.*action=plugin_information.*request%5Bslug%5D=akismet.*})
      .to_return({ status: 200, body: wordpress_plugin_information })
  end

  def wordpress_query_response
    {
      plugins: [
        { slug: 'akismet' },
        { slug: 'classic-editor' }
      ]
    }.to_json
  end

  def wordpress_plugin_information
    {
      slug: 'akismet',
      name: 'Akismet Anti-spam',
      short_description: 'Spam protection for WordPress.',
      homepage: 'https://akismet.com/',
      author: 'Automattic',
      author_profile: 'https://profiles.wordpress.org/automattic/',
      requires: '5.8',
      requires_php: '7.2',
      tested: '6.8',
      rating: 96,
      active_installs: 5_000_000,
      downloaded: 123456,
      download_link: 'https://downloads.wordpress.org/plugin/akismet.5.5.zip',
      tags: {
        spam: 'spam',
        security: 'security'
      },
      versions: {
        '5.5' => 'https://downloads.wordpress.org/plugin/akismet.5.5.zip',
        '5.4' => 'https://downloads.wordpress.org/plugin/akismet.5.4.zip'
      }
    }.to_json
  end
end
