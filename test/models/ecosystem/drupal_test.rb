require "test_helper"

class DrupalTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'drupal.org', url: 'https://www.drupal.org', ecosystem: 'drupal')
    @ecosystem = Ecosystem::Drupal.new(@registry)
    @package = Package.new(ecosystem: @registry.ecosystem, name: 'views')
    @version = @package.versions.build(number: '8.x-3.0')
  end

  test 'registry_url' do
    assert_equal 'https://www.drupal.org/project/views', @ecosystem.registry_url(@package)
  end

  test 'registry_url with version' do
    assert_equal 'https://www.drupal.org/project/views', @ecosystem.registry_url(@package, @version)
  end

  test 'download_url' do
    assert_equal 'https://ftp.drupal.org/files/projects/views-8.x-3.0.tar.gz', @ecosystem.download_url(@package, @version.number)
  end

  test 'documentation_url' do
    assert_equal 'https://www.drupal.org/project/views', @ecosystem.documentation_url(@package)
  end

  test 'install_command' do
    assert_equal 'composer require drupal/views', @ecosystem.install_command(@package)
  end

  test 'install_command with version' do
    assert_equal 'composer require drupal/views:8.x-3.0', @ecosystem.install_command(@package, @version.number)
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal 'pkg:drupal/views', purl
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, %r{https://www.drupal.org/api-d7/node.json\?.*type=project_module.*})
      .to_return({ status: 200, body: drupal_list_response })

    assert_equal ['views', 'token'], @ecosystem.all_package_names
  end

  test 'recently_updated_package_names' do
    stub_request(:get, %r{https://www.drupal.org/api-d7/node.json\?.*sort=changed.*})
      .to_return({ status: 200, body: drupal_list_response })

    assert_equal ['views', 'token'], @ecosystem.recently_updated_package_names
  end

  test 'package_metadata' do
    stub_drupal_module_lookup

    metadata = @ecosystem.package_metadata('views')

    assert_equal 'views', metadata[:name]
    assert_equal 'Create customized lists and queries from your database.', metadata[:description]
    assert_equal 'https://www.drupal.org/project/views', metadata[:homepage]
    assert_equal 'https://git.drupalcode.org/project/views', metadata[:repository_url]
    assert_equal ['administration', 'fields'], metadata[:keywords_array]
    assert_equal 'GPL-2.0-or-later', metadata[:licenses]
    assert_equal 1234567, metadata[:downloads]
    assert_equal 'total', metadata[:downloads_period]
    assert_equal ['8.x-3.0', '8.x-3.1'], metadata[:versions]
    assert_equal '1234', metadata[:metadata]['nid']
  end

  test 'versions_metadata' do
    stub_drupal_module_lookup

    metadata = @ecosystem.package_metadata('views')
    versions = @ecosystem.versions_metadata(metadata, ['8.x-3.0'])

    assert_equal 1, versions.length
    assert_equal '8.x-3.1', versions.first[:number]
    assert_equal 'GPL-2.0-or-later', versions.first[:licenses]
  end

  private

  def stub_drupal_module_lookup
    stub_request(:get, %r{https://www.drupal.org/api-d7/node.json\?.*field_project_machine_name=views.*})
      .to_return({ status: 200, body: { list: [drupal_module] }.to_json })
  end

  def drupal_list_response
    {
      list: [
        drupal_module,
        drupal_module.merge('field_project_machine_name' => 'token', 'title' => 'Token')
      ]
    }.to_json
  end

  def drupal_module
    {
      'nid' => '1234',
      'title' => 'Views',
      'field_project_machine_name' => 'views',
      'url' => 'https://www.drupal.org/project/views',
      'body' => { 'value' => 'Create customized lists and queries from your database.' },
      'field_project_repository' => 'https://git.drupalcode.org/project/views',
      'field_project_license' => 'GPL-2.0-or-later',
      'field_project_download_count' => 1_234_567,
      'field_project_type' => 'module',
      'created' => '1100000000',
      'changed' => '1700000000',
      'taxonomy_vocabulary_3' => [
        { 'name' => 'administration' },
        { 'name' => 'fields' }
      ],
      'field_project_releases' => [
        { 'version' => '8.x-3.0' },
        { 'version' => '8.x-3.1' }
      ],
      'field_project_maintainers' => [
        { 'name' => 'maintainer' }
      ]
    }
  end
end
