require "test_helper"

class BowerTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create(name: 'Bower.io', url: 'https://bower.io', ecosystem: 'bower')
    @ecosystem = Ecosystem::Bower.new(@registry)
    @package = @registry.packages.create(ecosystem: 'bower', name: 'bower-angular', repository_url: "https://github.com/angular/bower-angular")
    @version = @package.versions.create(number: '1.0.0', metadata: {download_url:"https://codeload.github.com/angular/bower-angular/tar.gz/refs/v1.0.0"})
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
    assert_equal download_url, "https://codeload.github.com/angular/bower-angular/tar.gz/refs/v1.0.0"
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

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:bower/bower-angular'
    assert PackageURL.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:bower/bower-angular@1.0.0'
    assert PackageURL.parse(purl)
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
      :repository_url=>"https://github.com/angular/bower-angular", 
      :licenses=>"MIT", 
      :keywords_array=>[], 
      :homepage=>'', 
      :description=>nil
    }
  end

  test 'versions_metadata' do
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://github.com/angular/bower-angular")
      .to_return({ status: 200, body: file_fixture('bower/lookup?url=https:%2F%2Fgithub.com%2Fangular%2Fbower-angular') })
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/hosts/GitHub/repositories/angular/bower-angular/tags")
      .to_return({ status: 200, body: file_fixture('bower/tags') })
    versions_metadata = @ecosystem.versions_metadata({name: 'bower-angular', repository_url: "https://github.com/angular/bower-angular"})

    assert_equal versions_metadata, [
      {:number=>"v1.2.8-build.2093+sha.1c045f1", :published_at=>"2014-01-08T09:03:50.000Z", :metadata=>{:sha=>"c7a4f380b36667b063d5f1b1dcb5aaebba43cf0c", :download_url=>"https://codeload.github.com/angular/bower-angular/tar.gz/v1.2.8-build.2093+sha.1c045f1"}},
      {:number=>"v1.2.8-build.2092+sha.95e1b2d", :published_at=>"2014-01-08T08:49:35.000Z", :metadata=>{:sha=>"24c0a22b32631277c6da4c419a484278e560c7a1", :download_url=>"https://codeload.github.com/angular/bower-angular/tar.gz/v1.2.8-build.2092+sha.95e1b2d"}}]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://raw.githubusercontent.com/advancedcontrol/composer/v2.5.1/bower.json")
      .to_return({ status: 200, body: file_fixture('bower/bower.json.1') })
    dependencies_metadata = @ecosystem.dependencies_metadata('composer', 'v2.5.1', {:name=>"composer", :repository_url=>"https://github.com/advancedcontrol/composer"})
    
    assert_equal dependencies_metadata, [
      {:package_name=>"angular", :requirements=>"1.x", :kind=>"runtime", :optional=>false, :ecosystem=>"bower"},
      {:package_name=>"angular-resource", :requirements=>"1.x", :kind=>"runtime", :optional=>false, :ecosystem=>"bower"},
      {:package_name=>"oauth-interceptor", :requirements=>"latest", :kind=>"runtime", :optional=>false, :ecosystem=>"bower"},
      {:package_name=>"spark-md5", :requirements=>"latest", :kind=>"runtime", :optional=>false, :ecosystem=>"bower"}
    ]
  end
end
