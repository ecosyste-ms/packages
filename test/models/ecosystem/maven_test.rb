
require "test_helper"

class MavenTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'repo1.maven.org', url: 'https://repo1.maven.org/maven2', ecosystem: 'maven')
    @ecosystem = Ecosystem::Maven.new(@registry.url)
    @package = Package.new(ecosystem: 'maven', name: 'dev.zio:zio-aws-autoscaling_3')
    @version = @package.versions.build(number: '5.17.224.2')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, "https://repo1.maven.org/maven2/dev/zio/zio-aws-autoscaling_3/"
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, "https://repo1.maven.org/maven2/dev/zio/zio-aws-autoscaling_3/5.17.224.2/"
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://repo1.maven.org/maven2/dev/zio/zio-aws-autoscaling_3/5.17.224.2/zio-aws-autoscaling_3-5.17.224.2.jar"
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
    assert_equal check_status_url, "https://repo1.maven.org/maven2/dev/zio/zio-aws-autoscaling_3/"
  end

  test 'all_package_names' do
    stub_request(:get, "https://repo1.maven.org/maven2/archetype-catalog.xml")
      .to_return({ status: 200, body: file_fixture('maven/archetype-catalog.xml') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 1
    assert_equal all_package_names.last, 'am.ik.archetype:elm-spring-boot-blank-archetype'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://repo1.maven.org/maven2/archetype-catalog.xml")
      .to_return({ status: 200, body: file_fixture('maven/archetype-catalog.xml') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 1
    assert_equal recently_updated_package_names.last, 'am.ik.archetype:elm-spring-boot-blank-archetype'
  end

  test 'package_metadata' do
    stub_request(:get, "https://repo1.maven.org/maven2/dev/zio/zio-aws-autoscaling_3/maven-metadata.xml")
      .to_return({ status: 200, body: file_fixture('maven/maven-metadata.xml') })
    stub_request(:get, "https://repo1.maven.org/maven2/dev/zio/zio-aws-autoscaling_3/5.17.225.2/zio-aws-autoscaling_3-5.17.225.2.pom")
      .to_return({ status: 200, body: file_fixture('maven/zio-aws-autoscaling_3-5.17.225.2.pom'), headers: { 'last-modified' => 'Tue, 12 Jul 2022 12:10:25 GMT' } })
    package_metadata = @ecosystem.package_metadata('dev.zio:zio-aws-autoscaling_3')

    assert_equal package_metadata[:name], "dev.zio:zio-aws-autoscaling_3"
    assert_equal package_metadata[:description], "Low-level AWS wrapper for ZIO"
    assert_equal package_metadata[:homepage], "https://github.com/zio/zio-aws"
    assert_equal package_metadata[:licenses], "APL2"
    assert_equal package_metadata[:repository_url], "https://github.com/zio/zio-aws"
    assert_nil package_metadata[:keywords_array]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://repo1.maven.org/maven2/dev/zio/zio-aws-autoscaling_3/maven-metadata.xml")
      .to_return({ status: 200, body: file_fixture('maven/maven-metadata.xml') })
    stub_request(:get, "https://repo1.maven.org/maven2/dev/zio/zio-aws-autoscaling_3/5.17.225.2/zio-aws-autoscaling_3-5.17.225.2.pom")
      .to_return({ status: 200, body: file_fixture('maven/zio-aws-autoscaling_3-5.17.225.2.pom'), headers: { 'last-modified' => 'Tue, 12 Jul 2022 12:10:25 GMT' } })
    stub_request(:get, "https://repo1.maven.org/maven2/dev/zio/zio-aws-autoscaling_3/5.17.102.7/zio-aws-autoscaling_3-5.17.102.7.pom")
      .to_return({ status: 200, body: file_fixture('maven/zio-aws-autoscaling_3-5.17.102.7.pom'), headers: { 'last-modified' => 'Tue, 12 Jul 2022 12:10:25 GMT' } })
    package_metadata = @ecosystem.package_metadata('dev.zio:zio-aws-autoscaling_3')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"5.17.102.7", :published_at=>"2022-07-12 12:10:25 +0000", :licenses=>["APL2"]},
      {:number=>"5.17.225.2", :published_at=>"2022-07-12 12:10:25 +0000", :licenses=>["APL2"]}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://repo1.maven.org/maven2/dev/zio/zio-aws-autoscaling_3/5.17.225.2/zio-aws-autoscaling_3-5.17.225.2.pom")
      .to_return({ status: 200, body: file_fixture('maven/zio-aws-autoscaling_3-5.17.225.2.pom'), headers: { 'last-modified' => 'Tue, 12 Jul 2022 12:10:25 GMT' } })

    dependencies_metadata = @ecosystem.dependencies_metadata('dev.zio:zio-aws-autoscaling_3', '5.17.225.2', {})

    assert_equal dependencies_metadata, [
      {:package_name=>"dev.zio:zio-aws-core_3", :requirements=>"5.17.225.2", :kind=>"runtime", :ecosystem=>"maven"},
      {:package_name=>"org.scala-lang:scala3-library_3", :requirements=>"3.1.3", :kind=>"runtime", :ecosystem=>"maven"},
      {:package_name=>"software.amazon.awssdk:autoscaling", :requirements=>"2.17.225", :kind=>"runtime", :ecosystem=>"maven"},
      {:package_name=>"dev.zio:zio_3", :requirements=>"2.0.0", :kind=>"runtime", :ecosystem=>"maven"},
      {:package_name=>"dev.zio:zio-streams_3", :requirements=>"2.0.0", :kind=>"runtime", :ecosystem=>"maven"},
      {:package_name=>"dev.zio:zio-mock_3", :requirements=>"1.0.0-RC8", :kind=>"runtime", :ecosystem=>"maven"}
    ]
  end
end
