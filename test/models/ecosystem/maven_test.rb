
require "test_helper"

class MavenTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'repo1.maven.org', url: 'https://repo1.maven.org/maven2', ecosystem: 'maven')
    @ecosystem = Ecosystem::Maven.new(@registry)
    @package = Package.new(ecosystem: 'maven', name: 'dev.zio:zio-aws-autoscaling_3')
    @version = @package.versions.build(number: '5.17.224.2')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, "https://central.sonatype.com/artifact/dev.zio/zio-aws-autoscaling_3/"
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, "https://central.sonatype.com/artifact/dev.zio/zio-aws-autoscaling_3/5.17.224.2"
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://repo1.maven.org/maven2/dev/zio/zio-aws-autoscaling_3/5.17.224.2/zio-aws-autoscaling_3-5.17.224.2.jar"
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, "https://appdoc.app/artifact/dev.zio/zio-aws-autoscaling_3/"
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_equal documentation_url, "https://appdoc.app/artifact/dev.zio/zio-aws-autoscaling_3/5.17.224.2"
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
    assert_equal check_status_url, "https://repo1.maven.org/maven2/dev/zio/zio-aws-autoscaling_3"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:maven/dev.zio/zio-aws-autoscaling_3'
    assert PackageURL.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:maven/dev.zio/zio-aws-autoscaling_3@5.17.224.2'
    assert PackageURL.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://repo1.maven.org/maven2/archetype-catalog.xml")
      .to_return({ status: 200, body: file_fixture('maven/archetype-catalog.xml') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 1
    assert_equal all_package_names.last, 'am.ik.archetype:elm-spring-boot-blank-archetype'
  end

  test 'recently_updated_package_names' do
    stub_request(:post, "https://central.sonatype.com/api/internal/browse/components?repository=maven-central")
      .with(
        body: "{\"size\":20,\"sortField\":\"publishedDate\",\"sortDirection\":\"desc\"}",
        headers: {
          'Content-Type'=>'application/json',
          'Expect'=>'',
          'User-Agent'=>'packages.ecosyste.ms'
        })
      .to_return(status: 200, body: '{"items":[]}', headers: {})
    stub_request(:get, "https://maven.libraries.io/mavenCentral/recent")
      .to_return({ status: 200, body: file_fixture('maven/recent') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 20
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
    assert_equal package_metadata[:namespace], "dev.zio"
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
      {:number=>"5.17.225.2", :published_at=>"2022-07-12 12:10:25 +0000", :licenses=>"APL2", 
       :metadata=>{:properties=>{}, :java_version=>nil, :maven_compiler_source=>nil, :maven_compiler_target=>nil, :maven_compiler_release=>nil, :repositories=>[], :distribution_repositories=>[]}},
      {:number=>"5.17.102.7", :published_at=>"2022-07-12 12:10:25 +0000", :licenses=>"APL2",
       :metadata=>{:properties=>{}, :java_version=>nil, :maven_compiler_source=>nil, :maven_compiler_target=>nil, :maven_compiler_release=>nil, :repositories=>[], :distribution_repositories=>[]}},
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

  test 'versions_metadata includes Java version metadata for Quarkus' do
    # Use the Quarkus parent POM fixture which has Java 11 configuration
    stub_request(:get, "https://repo1.maven.org/maven2/io/quarkus/quarkus-parent/maven-metadata.xml")
      .to_return({ status: 200, body: '<metadata><versioning><versions><version>3.2.0.Final</version></versions></versioning></metadata>' })
    stub_request(:get, "https://repo1.maven.org/maven2/io/quarkus/quarkus-parent/3.2.0.Final/quarkus-parent-3.2.0.Final.pom")
      .to_return({ status: 200, body: file_fixture('maven/quarkus-parent-3.2.0.Final.pom'), headers: { 'last-modified' => 'Tue, 12 Jul 2022 12:10:25 GMT' } })
    
    package_metadata = @ecosystem.package_metadata('io.quarkus:quarkus-parent')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)
    
    first_version = versions_metadata.first
    assert_equal first_version[:metadata][:java_version], "11"
    assert_equal first_version[:metadata][:maven_compiler_release], "11"
    assert_equal first_version[:metadata][:maven_compiler_source], "${maven.compiler.release}"
    assert_equal first_version[:metadata][:maven_compiler_target], "${maven.compiler.release}"
    assert first_version[:metadata][:properties].key?("maven.compiler.release")
    assert_equal first_version[:metadata][:properties]["maven.compiler.release"], "11"
  end

  test 'versions_metadata includes Java version metadata for Maven Compiler Plugin' do
    # Use the Maven Compiler Plugin POM fixture which has Java 8 configuration
    stub_request(:get, "https://repo1.maven.org/maven2/org/apache/maven/plugins/maven-compiler-plugin/maven-metadata.xml")
      .to_return({ status: 200, body: '<metadata><versioning><versions><version>3.11.0</version></versions></versioning></metadata>' })
    stub_request(:get, "https://repo1.maven.org/maven2/org/apache/maven/plugins/maven-compiler-plugin/3.11.0/maven-compiler-plugin-3.11.0.pom")
      .to_return({ status: 200, body: file_fixture('maven/maven-compiler-plugin-3.11.0.pom'), headers: { 'last-modified' => 'Tue, 12 Jul 2022 12:10:25 GMT' } })
    
    package_metadata = @ecosystem.package_metadata('org.apache.maven.plugins:maven-compiler-plugin')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)
    
    first_version = versions_metadata.first
    # This one has javaVersion property which takes precedence
    assert_equal first_version[:metadata][:java_version], "8"
    assert_equal first_version[:metadata][:maven_compiler_source], "1.8"
    assert_equal first_version[:metadata][:maven_compiler_target], "1.8"
    assert first_version[:metadata][:properties].key?("javaVersion")
    assert_equal first_version[:metadata][:properties]["javaVersion"], "8"
  end

  test 'versions_metadata includes Java 17 version metadata' do
    # Use the Java 17 example POM fixture
    stub_request(:get, "https://repo1.maven.org/maven2/com/example/java17-example/maven-metadata.xml")
      .to_return({ status: 200, body: '<metadata><versioning><versions><version>1.0.0</version></versions></versioning></metadata>' })
    stub_request(:get, "https://repo1.maven.org/maven2/com/example/java17-example/1.0.0/java17-example-1.0.0.pom")
      .to_return({ status: 200, body: file_fixture('maven/java17-example.pom'), headers: { 'last-modified' => 'Tue, 12 Jul 2022 12:10:25 GMT' } })
    
    package_metadata = @ecosystem.package_metadata('com.example:java17-example')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)
    
    first_version = versions_metadata.first
    assert_equal first_version[:metadata][:java_version], "17"
    assert_equal first_version[:metadata][:maven_compiler_release], "${java.version}"
    assert first_version[:metadata][:properties].key?("java.version")
    assert_equal first_version[:metadata][:properties]["java.version"], "17"
  end

  test 'non_maven_central_registry_url' do
    jboss_registry = Registry.new(name: 'repository.jboss.org', url: 'https://repository.jboss.org/nexus/content/repositories/releases', ecosystem: 'maven')
    jboss_ecosystem = Ecosystem::Maven.new(jboss_registry)
    
    registry_url = jboss_ecosystem.registry_url(@package)
    assert_equal registry_url, "https://repository.jboss.org/nexus/content/repositories/releases/dev/zio/zio-aws-autoscaling_3/"
  end

  test 'non_maven_central_registry_url_with_version' do
    jboss_registry = Registry.new(name: 'repository.jboss.org', url: 'https://repository.jboss.org/nexus/content/repositories/releases', ecosystem: 'maven')
    jboss_ecosystem = Ecosystem::Maven.new(jboss_registry)
    
    registry_url = jboss_ecosystem.registry_url(@package, @version)
    assert_equal registry_url, "https://repository.jboss.org/nexus/content/repositories/releases/dev/zio/zio-aws-autoscaling_3/5.17.224.2/"
  end

  test 'jboss_all_package_names_with_archetype_catalog' do
    jboss_registry = Registry.new(name: 'repository.jboss.org', url: 'https://repository.jboss.org/nexus/content/repositories/releases', ecosystem: 'maven')
    jboss_ecosystem = Ecosystem::Maven.new(jboss_registry)
    
    # Mock JBoss archetype-catalog.xml
    stub_request(:get, "https://repository.jboss.org/nexus/content/repositories/releases/archetype-catalog.xml")
      .to_return({ status: 200, body: file_fixture('maven/archetype-catalog.xml') })
    
    all_package_names = jboss_ecosystem.all_package_names
    assert_equal all_package_names.length, 1
    assert_equal all_package_names.last, 'am.ik.archetype:elm-spring-boot-blank-archetype'
  end


  test 'recently_updated_package_names_for_non_maven_central' do
    jboss_registry = Registry.new(name: 'repository.jboss.org', url: 'https://repository.jboss.org/nexus/content/repositories/releases', ecosystem: 'maven')
    jboss_ecosystem = Ecosystem::Maven.new(jboss_registry)
    
    # Mock JBoss archetype-catalog.xml (empty)
    stub_request(:get, "https://repository.jboss.org/nexus/content/repositories/releases/archetype-catalog.xml")
      .with(headers: { 'Expect' => '', 'User-Agent' => 'packages.ecosyste.ms' })
      .to_return({ status: 200, body: '<archetype-catalog><archetypes></archetypes></archetype-catalog>' })
    
    # Non-central registries with empty archetype catalog return empty array
    recent_packages = jboss_ecosystem.recently_updated_package_names
    assert_equal recent_packages, []
  end

  test 'apache_all_package_names_with_archetype_catalog' do
    apache_registry = Registry.new(name: 'repository.apache.org-releases', url: 'https://repository.apache.org/content/repositories/releases', ecosystem: 'maven')
    apache_ecosystem = Ecosystem::Maven.new(apache_registry)
    
    # Mock Apache archetype-catalog.xml
    stub_request(:get, "https://repository.apache.org/content/repositories/releases/archetype-catalog.xml")
      .to_return({ status: 200, body: file_fixture('maven/archetype-catalog.xml') })
    
    all_package_names = apache_ecosystem.all_package_names
    assert_equal all_package_names.length, 1
    assert_equal all_package_names.last, 'am.ik.archetype:elm-spring-boot-blank-archetype'
  end

  test 'extract_repository_urls_from_pom' do
    stub_request(:get, "https://repo1.maven.org/maven2/com/example/repository-example/maven-metadata.xml")
      .to_return({ status: 200, body: file_fixture('maven/repository-example-metadata.xml') })
    stub_request(:get, "https://repo1.maven.org/maven2/com/example/repository-example/1.0.0/repository-example-1.0.0.pom")
      .to_return({ status: 200, body: file_fixture('maven/repository-example.pom'), headers: { 'last-modified' => 'Tue, 12 Jul 2022 12:10:25 GMT' } })
    
    package_metadata = @ecosystem.package_metadata('com.example:repository-example')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)
    
    # Check package-level metadata
    assert_includes package_metadata[:metadata][:repositories], 'https://repository.jboss.org/nexus/content/repositories/releases'
    assert_includes package_metadata[:metadata][:repositories], 'https://repository.apache.org/content/repositories/snapshots'
    assert_includes package_metadata[:metadata][:distribution_repositories], 'https://nexus.example.com/repository/releases'
    assert_includes package_metadata[:metadata][:distribution_repositories], 'https://nexus.example.com/repository/snapshots'
    
    # Check version-level metadata
    first_version = versions_metadata.first
    assert_includes first_version[:metadata][:repositories], 'https://repository.jboss.org/nexus/content/repositories/releases'
    assert_includes first_version[:metadata][:repositories], 'https://repository.apache.org/content/repositories/snapshots'
    assert_includes first_version[:metadata][:distribution_repositories], 'https://nexus.example.com/repository/releases'
    assert_includes first_version[:metadata][:distribution_repositories], 'https://nexus.example.com/repository/snapshots'
  end

  test 'recently_updated_from_archetype_catalog_for_non_maven_central' do
    jboss_registry = Registry.new(name: 'repository.jboss.org', url: 'https://repository.jboss.org/nexus/content/repositories/releases', ecosystem: 'maven')
    jboss_ecosystem = Ecosystem::Maven.new(jboss_registry)
    
    # Mock JBoss archetype-catalog.xml with multiple packages
    catalog_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <archetype-catalog>
        <archetypes>
          <archetype>
            <groupId>org.jboss</groupId>
            <artifactId>jboss-archetype</artifactId>
            <version>1.0.0</version>
          </archetype>
          <archetype>
            <groupId>org.jboss</groupId>
            <artifactId>jboss-archetype</artifactId>
            <version>2.0.0</version>
          </archetype>
          <archetype>
            <groupId>org.wildfly</groupId>
            <artifactId>wildfly-archetype</artifactId>
            <version>1.5.0</version>
          </archetype>
        </archetypes>
      </archetype-catalog>
    XML
    
    stub_request(:get, "https://repository.jboss.org/nexus/content/repositories/releases/archetype-catalog.xml")
      .with(headers: { 'Expect' => '', 'User-Agent' => 'packages.ecosyste.ms' })
      .to_return({ status: 200, body: catalog_xml })
    
    recent_packages = jboss_ecosystem.recently_updated_package_names
    
    # Should return unique package names from archetype catalog (all packages are "missing" since no DB lookup in test)
    assert_includes recent_packages, 'org.jboss:jboss-archetype'
    assert_includes recent_packages, 'org.wildfly:wildfly-archetype'
    assert_equal recent_packages.length, 2
  end

  test 'apache_snapshots_package_metadata_and_repository_extraction' do
    apache_snapshots_registry = Registry.new(name: 'repository.apache.org-snapshots', url: 'https://repository.apache.org/content/repositories/snapshots', ecosystem: 'maven')
    apache_snapshots_ecosystem = Ecosystem::Maven.new(apache_snapshots_registry)
    
    # Mock Apache snapshots maven-metadata.xml and POM
    stub_request(:get, "https://repository.apache.org/content/repositories/snapshots/org/apache/maven/archetypes/maven-archetype-profiles/maven-metadata.xml")
      .to_return({ status: 200, body: file_fixture('maven/apache-snapshots-metadata.xml') })
    stub_request(:get, "https://repository.apache.org/content/repositories/snapshots/org/apache/maven/archetypes/maven-archetype-profiles/1.3-SNAPSHOT/maven-archetype-profiles-1.3-SNAPSHOT.pom")
      .to_return({ status: 200, body: file_fixture('maven/apache-snapshots.pom'), headers: { 'last-modified' => 'Sat, 24 Mar 2018 12:19:00 GMT' } })
    stub_request(:get, "https://repository.apache.org/content/repositories/snapshots/org/apache/maven/archetypes/maven-archetype-profiles/1.0-SNAPSHOT/maven-archetype-profiles-1.0-SNAPSHOT.pom")
      .to_return({ status: 200, body: file_fixture('maven/apache-snapshots.pom'), headers: { 'last-modified' => 'Sat, 24 Mar 2018 12:19:00 GMT' } })
    
    # Mock parent POM request (referenced in our test POM)
    stub_request(:get, "https://repository.apache.org/content/repositories/snapshots/org/apache/maven/archetypes/maven-archetype-bundles/1.3-SNAPSHOT/maven-archetype-bundles-1.3-SNAPSHOT.pom")
      .to_return({ status: 404 })
    
    # Test package metadata fetching
    package_metadata = apache_snapshots_ecosystem.package_metadata('org.apache.maven.archetypes:maven-archetype-profiles')
    
    assert_equal package_metadata[:name], 'org.apache.maven.archetypes:maven-archetype-profiles'
    assert_equal package_metadata[:description], 'An archetype which contains a sample Maven project which demonstrates the use of profiles.'
    assert_equal package_metadata[:namespace], 'org.apache.maven.archetypes'
    
    # Test repository URL extraction from package-level metadata
    assert_includes package_metadata[:metadata][:repositories], 'https://repository.apache.org/content/repositories/snapshots'
    assert_includes package_metadata[:metadata][:distribution_repositories], 'https://repository.apache.org/content/repositories/releases'
    assert_includes package_metadata[:metadata][:distribution_repositories], 'https://repository.apache.org/content/repositories/snapshots'
    
    # Test version metadata
    versions_metadata = apache_snapshots_ecosystem.versions_metadata(package_metadata)
    
    assert_equal versions_metadata.length, 2
    assert_equal versions_metadata.first[:number], '1.3-SNAPSHOT'
    assert_equal versions_metadata.last[:number], '1.0-SNAPSHOT'
    
    # Test repository URL extraction from version-level metadata
    first_version = versions_metadata.first
    assert_includes first_version[:metadata][:repositories], 'https://repository.apache.org/content/repositories/snapshots'
    assert_includes first_version[:metadata][:distribution_repositories], 'https://repository.apache.org/content/repositories/releases'
    assert_includes first_version[:metadata][:distribution_repositories], 'https://repository.apache.org/content/repositories/snapshots'
  end


end
