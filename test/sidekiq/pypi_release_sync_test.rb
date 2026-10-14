require 'test_helper'

class PypiReleaseSyncTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create!(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    @package = @registry.packages.create!(name: 'pbr', ecosystem: 'pypi')
    @releases = {
      '7.0.3' => [release_file('7.0.3', '2025-11-03T17:04:54', false)],
      '7.1.2' => [release_file('7.1.2', '2026-08-25T12:38:42', true)]
    }
    stub_request(:get, 'https://pypi.org/pypi/pbr/json').to_return do
      { status: 200, body: { info: { name: 'pbr', license: 'Apache-2.0' }, releases: @releases }.to_json }
    end
    stub_request(:get, 'https://pypistats.org/api/packages/pbr/recent')
      .to_return(status: 200, body: { data: { last_month: 100 } }.to_json)
    stub_request(:get, %r{https://pypi.org/pypi/pbr/[^/]+/json})
      .to_return(status: 200, body: { info: { license: 'Apache-2.0', requires_dist: [] } }.to_json)
  end

  %i[full versions].each do |mode|
    test "#{mode} sync excludes newly imported yanked releases" do
      sync_package(mode)

      assert_latest_release '7.0.3'
      assert_equal 2, @package.versions.count
      version = @package.versions.find_by!(number: '7.1.2')
      assert_equal 'yanked', version.status
      assert_equal true, version.metadata['yanked']
      assert_equal 'Broken build', version.metadata['yanked_reason']
    end

    test "#{mode} sync updates existing releases when yanked and restored" do
      @releases['7.1.2'].first.merge!('yanked' => false, 'yanked_reason' => nil)
      sync_package(mode)
      assert_latest_release '7.1.2'
      version = @package.versions.find_by!(number: '7.1.2')
      original = version.attributes.slice('integrity', 'licenses', 'published_at')

      [true, false].each do |yanked|
        @releases['7.1.2'].first.merge!('yanked' => yanked, 'yanked_reason' => yanked ? 'Broken build' : nil)
        sync_package(mode)

        assert_latest_release(yanked ? '7.0.3' : '7.1.2')
        version.reload
        if yanked
          assert_equal 'yanked', version.status
          assert_equal 'Broken build', version.metadata['yanked_reason']
        else
          assert_nil version.status
          assert_nil version.metadata['yanked_reason']
        end
        assert_equal yanked, version.metadata['yanked']
        assert_equal original, version.attributes.slice('integrity', 'licenses', 'published_at')
      end

      if mode == :full
        assert_requested :get, 'https://pypi.org/pypi/pbr/7.1.2/json', times: 1
      end
      assert_requested :get, 'https://pypi.org/pypi/pbr/json', times: mode == :full ? 6 : 3
    end

    test "#{mode} sync keeps releases with an unyanked file eligible" do
      sync_package(mode)
      @releases['7.1.2'] << release_file('7.1.2', '2026-08-25T12:38:42', false)

      sync_package(mode)

      assert_latest_release '7.1.2'
      assert_nil @package.versions.find_by!(number: '7.1.2').status
    end

    test "#{mode} sync clears latest when all releases are yanked" do
      sync_package(mode)
      @releases['7.0.3'].first.merge!('yanked' => true, 'yanked_reason' => 'Broken build')

      sync_package(mode)

      assert_nil @package.reload.latest_release_number
      assert_empty @package.versions.where(latest: true)
      assert_equal ['yanked'], @package.versions.distinct.pluck(:status)
    end

    test "#{mode} sync imports releases without files alongside yanked releases" do
      @releases['6.0.0'] = []

      sync_package(mode)

      assert_latest_release '7.0.3'
      version = @package.versions.find_by!(number: '6.0.0')
      assert_nil version.status
      assert_nil version.integrity
    end
  end

  def sync_package(mode)
    if mode == :full
      SyncPackageWorker.new.perform(@registry.id, @package.name, true)
    else
      UpdateVersionsWorker.new.perform(@package.id)
    end
  end

  def assert_latest_release(number)
    assert_equal number, @package.reload.latest_release_number
    assert_equal Time.iso8601(@releases[number].first['upload_time'] + 'Z'), @package.latest_release_published_at
    assert_equal [number], @package.versions.where(latest: true).pluck(:number)
  end

  def release_file(number, published_at, yanked)
    {
      'upload_time' => published_at,
      'digests' => { 'sha256' => number.delete('.').ljust(64, '0') },
      'url' => "https://files.pythonhosted.org/packages/pbr-#{number}.tar.gz",
      'yanked' => yanked,
      'yanked_reason' => yanked ? 'Broken build' : nil,
      'packagetype' => 'sdist',
      'python_version' => 'source'
    }
  end
end
