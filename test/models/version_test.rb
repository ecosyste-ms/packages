require "test_helper"

class VersionTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:package)
    should have_many(:dependencies)
    should have_many(:artifacts)
  end

  context 'validations' do
    should validate_presence_of(:package_id)
    should validate_presence_of(:number)
    should validate_uniqueness_of(:number).scoped_to(:package_id).case_insensitive
  end

  setup do 
    @registry = Registry.create(default: true, name: 'Rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
    @package = @registry.packages.create(name: 'foo', ecosystem: @registry.ecosystem)
    @version = @package.versions.create(number: '1.0.0', created_at: Time.now)
    @version2 = @package.versions.create(number: '2.0.0', created_at: 1.week.ago)
  end

  test 'published_at' do
    assert_equal @version.published_at, @version.created_at
  end

  test 'immutable reads version metadata' do
    @version.update!(metadata: { immutable: false })

    assert_equal false, @version.immutable
  end

  test 'sort' do
    sorted = [@version, @version2].sort
    assert_equal sorted.first, @version2
  end
  
  test 'to_s' do
    assert_equal @version.to_s, @version.number
  end

  test 'semantic_version' do
    assert_equal @version.semantic_version.class, Semantic::Version
  end

  test 'download_url' do
    assert_equal @version.download_url, 'https://rubygems.org/downloads/foo-1.0.0.gem'
  end

  test 'install_command' do
    assert_equal @version.install_command, 'gem install foo -s https://rubygems.org -v 1.0.0'
  end

  test 'registry_url' do
    assert_equal @version.registry_url, 'https://rubygems.org/gems/foo/versions/1.0.0'
  end

  test 'documentation_url' do
    assert_equal @version.documentation_url, "http://www.rubydoc.info/gems/foo/1.0.0"
  end

  test 'purl' do
    assert_equal @version.purl, "pkg:gem/foo@1.0.0"
    assert Purl.parse(@version.purl)
  end

  test 'version scoped advisories include only affected advisory entries' do
    @package.update!(advisories: [
      {
        "uuid" => "GHSA-affected",
        "identifiers" => ["GHSA-affected", "CVE-2026-0001"],
        "url" => "https://github.com/advisories/GHSA-affected",
        "title" => "Affected advisory",
        "severity" => "high",
        "packages" => [
          {
            "ecosystem" => "rubygems",
            "package_name" => "foo",
            "versions" => [
              { "vulnerable_version_range" => ">= 1.0.0, < 2.0.0", "first_patched_version" => "2.0.0" }
            ]
          }
        ]
      },
      {
        "uuid" => "GHSA-fixed",
        "identifiers" => ["GHSA-fixed"],
        "packages" => [
          {
            "ecosystem" => "rubygems",
            "package_name" => "foo",
            "versions" => [
              { "vulnerable_version_range" => "< 1.0.0", "first_patched_version" => nil }
            ]
          }
        ]
      },
      {
        "uuid" => "GHSA-other-package",
        "identifiers" => ["GHSA-other-package"],
        "packages" => [
          {
            "ecosystem" => "rubygems",
            "package_name" => "bar",
            "versions" => [
              { "vulnerable_version_range" => ">= 1.0.0" }
            ]
          }
        ]
      }
    ])

    assert_equal [
      {
        "uuid" => "GHSA-affected",
        "identifiers" => ["GHSA-affected", "CVE-2026-0001"],
        "url" => "https://github.com/advisories/GHSA-affected",
        "title" => "Affected advisory",
        "severity" => "high",
        "affected" => true,
        "fixed" => false,
        "fixed_versions" => ["2.0.0"]
      }
    ], @version.version_scoped_advisories

    assert_empty @version2.version_scoped_advisories
  end

  test 'version scoped advisories skip invalid version ranges' do
    @package.update!(advisories: [
      {
        "uuid" => "GHSA-invalid",
        "identifiers" => ["GHSA-invalid"],
        "packages" => [
          {
            "ecosystem" => "rubygems",
            "package_name" => "foo",
            "versions" => [{ "vulnerable_version_range" => "not a range" }]
          }
        ]
      }
    ])

    assert_empty @version.version_scoped_advisories
  end

  test 'version scoped advisories support short version numbers' do
    short_version = @package.versions.create!(number: "1.0")
    @package.update!(advisories: [
      {
        "uuid" => "GHSA-short-version",
        "identifiers" => ["GHSA-short-version"],
        "packages" => [
          {
            "ecosystem" => "rubygems",
            "package_name" => "foo",
            "versions" => [{ "vulnerable_version_range" => ">= 1.0, < 2.0" }]
          }
        ]
      }
    ])

    assert_equal ["GHSA-short-version"], short_version.version_scoped_advisories.pluck("uuid")
  end

  test 'version scoped advisories support Composer ranges' do
    registry = Registry.create!(default: true, name: "packagist.org", url: "https://packagist.org", ecosystem: "packagist")
    package = registry.packages.create!(name: "vendor/package", ecosystem: "packagist")
    version = package.versions.create!(number: "1.2.3")
    package.update!(advisories: [
      {
        "uuid" => "GHSA-composer-range",
        "identifiers" => ["GHSA-composer-range"],
        "packages" => [
          {
            "ecosystem" => "packagist",
            "package_name" => "vendor/package",
            "versions" => [{ "vulnerable_version_range" => "^1.0" }]
          }
        ]
      }
    ])

    assert_equal ["GHSA-composer-range"], version.version_scoped_advisories.pluck("uuid")
  end

  test 'as_live_event_json includes API fields' do
    json = @version.as_live_event_json

    assert_equal '1.0.0', json['number']
    assert_equal 'pkg:gem/foo@1.0.0', json['purl']
    assert_equal 'https://rubygems.org/downloads/foo-1.0.0.gem', json['download_url']
    assert_equal 'https://rubygems.org/gems/foo/versions/1.0.0', json['registry_url']
    assert json.key?('published_at')
    assert json.key?('integrity')
    assert json.key?('status')
    refute json.key?('dependencies')
  end

  test 'sync_artifacts upserts by identifier' do
    artifacts_metadata = [
      {
        identifier: 'foo-1.0.0.gem',
        filename: 'foo-1.0.0.gem',
        kind: 'gem',
        integrity: "sha256-#{'a' * 64}"
      }
    ]

    @version.sync_artifacts(artifacts_metadata)
    @version.sync_artifacts(artifacts_metadata.first.merge(size: 123).then { |artifact| [artifact] })

    assert_equal 1, @version.artifacts.count
    assert_equal 123, @version.artifacts.first.size
  end

  test 'sync_artifacts marks missing artifacts as removed' do
    @version.sync_artifacts([{ identifier: 'old.gem' }, { identifier: 'current.gem' }])

    @version.sync_artifacts([{ identifier: 'current.gem' }])

    assert_equal 'removed', @version.artifacts.find_by!(identifier: 'old.gem').status
    assert_nil @version.artifacts.find_by!(identifier: 'current.gem').status
  end

  test 'sync_artifacts leaves artifacts unchanged when metadata is unsupported' do
    artifact = @version.artifacts.create!(identifier: 'foo-1.0.0.gem')

    @version.sync_artifacts(nil)

    assert_nil artifact.reload.status
  end

  test 'sync_artifacts requires an identifier' do
    assert_raises ArgumentError do
      @version.sync_artifacts([{ filename: 'foo-1.0.0.gem' }])
    end
  end

  test 'sync_artifacts keeps the last duplicate identifier' do
    @version.sync_artifacts([
      { identifier: 'foo-1.0.0.gem', size: 100 },
      { identifier: 'foo-1.0.0.gem', size: 200 }
    ])

    assert_equal 1, @version.artifacts.count
    assert_equal 200, @version.artifacts.first.size
  end
end
