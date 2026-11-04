require 'test_helper'

class RegistryCleanupTest < ActiveSupport::TestCase
  class LicenseCleanup < RegistryCleanup
    STATE_KEY = 'license_cleanup'.freeze

    def initial_counters
      {'licenses_updated' => 0}
    end

    def preview_package(package)
      {license: package&.licenses}
    end

    def prepare_package(_registry, package)
      package.licenses.upcase
    end

    def repair_package(_registry, package, license)
      changed = package.licenses != license
      package.update!(licenses: license)
      raise 'License repair failed' if package.metadata['fail']
      {licenses_updated: changed ? 1 : 0}
    end
  end

  class MetadataCleanup < RegistryCleanup
    STATE_KEY = 'metadata_cleanup'.freeze

    def repair_package(_registry, package, _prepared)
      package.update!(metadata: package.metadata.merge('checked' => true))
      {}
    end
  end

  setup do
    @registry = Registry.create!(name: 'rubygems.org', url: 'https://rubygems.org', ecosystem: 'Rubygems')
    @output = StringIO.new
  end

  test 'another ecosystem can preview native package names without Composer validation' do
    registry = Registry.create!(name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    package = registry.packages.create!(name: '@scope/library', ecosystem: 'npm', licenses: 'mit')
    before = package.attributes

    result = LicenseCleanup.new(registry, name: '@SCOPE/LIBRARY', output: @output).run

    preview = @output.string.lines.map { |line| JSON.parse(line) }.find { |row| row['event'] == 'preview' }
    assert_equal package.id, preview['id']
    assert_equal 'mit', preview['license']
    assert_equal 1, result[:attempted]
    assert_equal 0, result[:licenses_updated]
    assert_equal before, package.reload.attributes
    assert_nil registry.reload.metadata['license_cleanup']
    assert_not_requested(:get, %r{https://})
  end

  test 'another ecosystem resumes bounded repairs and accumulates its own counters' do
    first = @registry.packages.create!(name: 'rack', ecosystem: 'rubygems', licenses: 'mit')
    second = @registry.packages.create!(name: 'rails', ecosystem: 'rubygems', licenses: 'mit')

    first_result = LicenseCleanup.new(@registry, dry_run: false, limit: 1, pause: 0, output: @output).run
    second_result = LicenseCleanup.new(@registry, dry_run: false, limit: 1, pause: 0, output: @output).run

    assert_equal 1, first_result[:licenses_updated]
    assert_not first_result[:complete]
    assert_equal 2, second_result[:licenses_updated]
    assert_equal 2, second_result[:processed]
    assert second_result[:complete]
    assert_equal ['MIT', 'MIT'], [first.reload.licenses, second.reload.licenses]
    assert_equal second.name, @registry.reload.metadata.dig('license_cleanup', 'all', 'after_name')
    assert_nil @registry.metadata['packagist_cleanup']
    assert_not second_result.key?(:platform_dependencies_removed)
  end

  test 'another ecosystem rolls back failed repairs and retries without double counting' do
    package = @registry.packages.create!(name: 'rack', ecosystem: 'rubygems', licenses: 'mit', metadata: {'fail' => true})

    failed = LicenseCleanup.new(@registry, dry_run: false, pause: 0, output: @output).run

    assert_equal 'mit', package.reload.licenses
    assert_equal 0, failed[:processed]
    assert_equal 0, failed[:licenses_updated]
    assert_equal [package.id.to_s], failed[:failures].keys
    package.update!(metadata: {})

    retried = LicenseCleanup.new(@registry, dry_run: false, pause: 0, output: @output).run

    assert_equal 'MIT', package.reload.licenses
    assert_equal 1, retried[:processed]
    assert_equal 1, retried[:licenses_updated]
    assert_empty retried[:failures]
    assert retried[:complete]
  end

  test 'cleanup operations keep separate checkpoints within the same registry' do
    package = @registry.packages.create!(name: 'rack', ecosystem: 'rubygems', licenses: 'mit')

    LicenseCleanup.new(@registry, dry_run: false, pause: 0, output: @output).run
    metadata = MetadataCleanup.new(@registry, dry_run: false, pause: 0, output: @output).run

    assert_equal 'MIT', package.reload.licenses
    assert package.metadata['checked']
    assert_equal 1, metadata[:processed]
    assert_not metadata.key?(:licenses_updated)
    assert_equal 1, @registry.reload.metadata.dig('license_cleanup', 'all', 'processed')
    assert_equal 1, @registry.metadata.dig('metadata_cleanup', 'all', 'processed')
  end

  test 'all cleanup operations share the registry lock' do
    connection = PG.connect(Registry.connection.raw_connection.conninfo_hash.compact)
    connection.exec_params('SELECT pg_advisory_lock(hashtextextended($1, 0))', ["registry_cleanup:#{@registry.id}"])

    assert_raises(RuntimeError) { LicenseCleanup.new(@registry, output: @output).run }
    assert_raises(RuntimeError) { MetadataCleanup.new(@registry, output: @output).run }
  ensure
    connection&.close
  end

  test 'single component names support case insensitive scope and preserve other records' do
    selected = @registry.packages.create!(name: 'Rack', ecosystem: 'rubygems', licenses: 'mit')
    other = @registry.packages.create!(name: 'rails', ecosystem: 'rubygems', licenses: 'mit')

    result = LicenseCleanup.new(@registry, name: 'RACK', dry_run: false, pause: 0, output: @output).run

    assert_equal 1, result[:processed]
    assert_equal 'MIT', selected.reload.licenses
    assert_equal 'mit', other.reload.licenses
  end
end
