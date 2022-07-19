
require "test_helper"

class ClojarsTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'clojars.org', url: 'https://repo.clojars.org', ecosystem: 'clojars')
    @ecosystem = Ecosystem::Clojars.new(@registry.url)
    @package = Package.new(ecosystem: 'clojars', name: 'missionary')
    @version = @package.versions.build(number: 'b.26')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, "https://clojars.org/missionary/"
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, "https://clojars.org/missionary/versions/b.26"
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://repo.clojars.org/missionary/missionary/b.26/missionary-b.26.jar"
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
    assert_equal check_status_url, "https://clojars.org/missionary/"
  end

  test 'all_package_names' do
    stub_request(:get, "https://repo.clojars.org/all-poms.txt")
      .to_return({ status: 200, body: file_fixture('clojars/all-poms.txt') })
    all_package_names = @ecosystem.all_package_names

    assert_equal all_package_names.length, 29151
    assert_equal all_package_names.last, 'zyzanie'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://clojars.org/")
      .to_return({ status: 200, body: file_fixture('clojars/index.html') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 6
    assert_equal recently_updated_package_names.first, 'de.active-group/reacl-c'
  end

  test 'package_metadata' do
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/maven-metadata.xml")
      .to_return({ status: 200, body: file_fixture('clojars/maven-metadata.xml') })
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/b.26/missionary-b.26.pom")
      .to_return({ status: 200, body: file_fixture('clojars/missionary-b.26.pom'), headers: { 'last-modified' => 'Tue, 11 Jan 2022 14:34:47 GMT' }  })
    package_metadata = @ecosystem.package_metadata('missionary')

    assert_equal package_metadata[:name], "missionary"
    assert_equal package_metadata[:description], "A functional effect and streaming system for clojure and clojurescript."
    assert_equal package_metadata[:homepage], "https://github.com/leonoel/missionary"
    assert_equal package_metadata[:licenses], "Eclipse Public License"
    assert_equal package_metadata[:repository_url], "https://github.com/leonoel/missionary"
    assert_nil package_metadata[:keywords_array]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/maven-metadata.xml")
      .to_return({ status: 200, body: file_fixture('clojars/maven-metadata.xml') })
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/b.26/missionary-b.26.pom")
      .to_return({ status: 200, body: file_fixture('clojars/missionary-b.26.pom'), headers: { 'last-modified' => 'Tue, 11 Jan 2022 14:34:47 GMT' }  })
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/b.25/missionary-b.25.pom")
      .to_return({ status: 200, body: file_fixture('clojars/missionary-b.25.pom'), headers: { 'last-modified' => 'Fri, 24 Dec 2021 08:31:43 GMT' }  })

    package_metadata = @ecosystem.package_metadata('missionary')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"b.25", :published_at=>'2021-12-24 08:31:43 +0000', :licenses=>["Eclipse Public License"]},
      {:number=>"b.26", :published_at=>'2022-01-11 14:34:47 +0000', :licenses=>["Eclipse Public License"]}
  ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/b.26/missionary-b.26.pom")
      .to_return({ status: 200, body: file_fixture('clojars/missionary-b.26.pom') })

    dependencies_metadata = @ecosystem.dependencies_metadata('missionary', 'b.26', {})

    assert_equal dependencies_metadata, [
      {:package_name=>"org.clojure:clojure", :requirements=>"1.10.3", :kind=>"runtime", :ecosystem=>"clojars"},
      {:package_name=>"org.clojure:clojurescript", :requirements=>"1.10.879", :kind=>"runtime", :ecosystem=>"clojars"},
      {:package_name=>"org.reactivestreams:reactive-streams", :requirements=>"1.0.3", :kind=>"runtime", :ecosystem=>"clojars"},
      {:package_name=>"cloroutine", :requirements=>"10", :kind=>"runtime", :ecosystem=>"clojars"}
    ]
  end
end
