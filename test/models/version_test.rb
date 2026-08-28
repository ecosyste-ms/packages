require "test_helper"

class VersionTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:package)
    should have_many(:dependencies)
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

  test 'sorts versions using package ecosystem precedence' do
    cases = [
      { ecosystem: 'pypi', lower: '1.0', higher: '1.0.post1' },
      { ecosystem: 'maven', lower: '1.0', higher: '1.0-sp1' },
      { ecosystem: 'cargo', lower: '1.0.0+1', higher: '1.0.0+2' },
      { ecosystem: 'ubuntu', lower: '1.0~rc1', higher: '1.0' },
      { ecosystem: 'postmarketos', lower: '1.0-r2', higher: '1.0-r10' }
    ]

    cases.each do |version_case|
      ecosystem = version_case.fetch(:ecosystem)
      registry = Registry.create!(name: "#{ecosystem}.example", url: "https://#{ecosystem}.example", ecosystem: ecosystem)
      package = registry.packages.create!(name: 'example', ecosystem: ecosystem)
      versions = [
        package.versions.create!(number: version_case.fetch(:lower), published_at: 1.day.ago),
        package.versions.create!(number: version_case.fetch(:higher), published_at: 2.days.ago)
      ]

      assert_equal [version_case.fetch(:higher), version_case.fetch(:lower)], versions.sort.map(&:number), ecosystem
    end
  end

  test 'classifies stable versions using package ecosystem rules' do
    cases = [
      { ecosystem: 'pypi', stable: '1.0.post1', prerelease: '1.0rc1' },
      { ecosystem: 'maven', stable: '1.0-sp1', prerelease: '1.0-rc1' }
    ]

    cases.each do |version_case|
      ecosystem = version_case.fetch(:ecosystem)
      registry = Registry.create!(name: "#{ecosystem}.stable.example", url: "https://#{ecosystem}.stable.example", ecosystem: ecosystem)
      package = registry.packages.create!(name: 'example', ecosystem: ecosystem)

      assert package.versions.build(number: version_case.fetch(:stable)).stable?, ecosystem
      refute package.versions.build(number: version_case.fetch(:prerelease)).stable?, ecosystem
    end
  end

  test 'sorts Bazel module versions by Bazel precedence' do
    registry = Registry.create!(name: 'registry.bazel.build', url: 'https://registry.bazel.build', ecosystem: 'Bazel')
    package = registry.packages.create!(name: 'protobuf', ecosystem: 'bazel')
    versions = ['36.0', '36.0.bcr.10', '36.0-rc2', '36.0.bcr.2'].map do |number|
      package.versions.create!(number: number)
    end

    assert_equal ['36.0.bcr.10', '36.0.bcr.2', '36.0', '36.0-rc2'], versions.sort.map(&:number)
  end

  test 'sorts equivalent versions deterministically' do
    registry = Registry.create!(name: 'registry.bazel.build', url: 'https://registry.bazel.build', ecosystem: 'Bazel')
    package = registry.packages.create!(name: 'protobuf', ecosystem: 'bazel')
    published_at = 1.day.ago
    versions = [
      package.versions.create!(number: '1.0+build9', published_at: 2.days.ago),
      package.versions.create!(number: '1.0+build2', published_at: published_at),
      package.versions.create!(number: '1.0+build3', published_at: published_at)
    ]
    expected = ['1.0+build3', '1.0+build2', '1.0+build9']

    assert_equal expected, versions.sort.map(&:number)
    assert_equal expected, versions.reverse.sort.map(&:number)
  end

  test 'classifies Bazel module releases and prereleases' do
    registry = Registry.create!(name: 'registry.bazel.build', url: 'https://registry.bazel.build', ecosystem: 'Bazel')
    package = registry.packages.create!(name: 'protobuf', ecosystem: 'bazel')

    assert package.versions.build(number: '35.1').stable?
    assert package.versions.build(number: '36.0.bcr.1').stable?
    refute package.versions.build(number: '36.0-rc2').stable?
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
end
