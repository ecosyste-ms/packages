require "test_helper"

class BowerTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create(name: 'Bower.io', url: 'https://bower.io', ecosystem: 'bower')
    @ecosystem = Ecosystem::Bower.new(@registry.url)
    @package = @registry.packages.create(ecosystem: 'bower', name: 'bower-angular', repository_url: "https://github.com/angular/bower-angular.git")
    @version = @package.versions.create(number: '1.0.0')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_nil registry_url
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, '1.0.0')
    assert_nil registry_url
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://codeload.github.com/angular/bower-angular/tar.gz/refs/heads/master"
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_nil documentation_url
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, '1.0.0')
    assert_nil documentation_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'bower install bower-angular'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, '1.0.0')
    assert_equal install_command, 'bower install bower-angular#1.0.0'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_nil check_status_url
  end

  test 'all_package_names' do
    stub_request(:get, "https://registry.bower.io/packages")
      .to_return({ status: 200, body: file_fixture('bower/packages') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 70212
    assert_equal all_package_names.last, 'zzxcxc'
  end

  test 'recently_updated_package_names' do
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 0
    assert_nil recently_updated_package_names.last
  end
  
  test 'package_metadata' do
    stub_request(:get, "https://registry.bower.io/packages")
      .to_return({ status: 200, body: file_fixture('bower/packages') })
    stub_request(:get, "https://raw.githubusercontent.com/angular/bower-angular/master/bower.json")
      .to_return({ status: 200, body: file_fixture('bower/bower.json') })
    package_metadata = @ecosystem.package_metadata('bower-angular')

    assert_equal package_metadata, {
      :name=>"bower-angular", 
      :repository_url=>"https://github.com/angular/bower-angular.git", 
      :licenses=>"MIT", 
      :keywords_array=>nil, 
      :homepage=>nil, 
      :description=>nil
    }
  end

  test 'versions_metadata' do
    versions_metadata = @ecosystem.versions_metadata({name: 'bower-angular'})

    assert_equal versions_metadata, []
  end

  test 'dependencies_metadata' do
    dependencies_metadata = @ecosystem.dependencies_metadata('bower-angular', '0.3.0', nil)
    
    assert_equal dependencies_metadata, []
  end
end
