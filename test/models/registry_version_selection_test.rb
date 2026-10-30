require 'test_helper'

class RegistryVersionSelectionTest < ActiveSupport::TestCase
  [
    ['glog', %w[0.7.1 0.7.1.bcr.1 0.7.1.bcr.2], {}, '0.7.1.bcr.2'],
    ['protobuf', %w[3.19.6 35.1 36.0-rc2 36.0 36.0.bcr.1], { '36.0' => 'Use the patched release' }, '36.0.bcr.1']
  ].each do |name, numbers, yanked, expected|
    test "Bazel sync persists the latest active #{name} release" do
      registry = Registry.create!(name: 'registry.bazel.build', url: 'https://registry.bazel.build', ecosystem: 'Bazel')
      stub_request(:get, "https://bcr.bazel.build/modules/#{name}/metadata.json").to_return(
        status: 200,
        body: { versions: numbers, yanked_versions: yanked, maintainers: [], repository: [] }.to_json
      )
      numbers.each do |number|
        stub_request(:get, "https://bcr.bazel.build/modules/#{name}/#{number}/source.json")
          .to_return(status: 200, body: '{}')
        stub_request(:get, "https://bcr.bazel.build/modules/#{name}/#{number}/MODULE.bazel")
          .to_return(status: 200, body: "module(name = \"#{name}\", version = \"#{number}\")")
      end
      Package.any_instance.stubs(:check_status)

      package = registry.sync_package(name).reload

      assert_equal expected, package.latest_release_number
      assert_equal [expected], package.versions.where(latest: true).pluck(:number)
      yanked.each_key { |number| assert_equal 'yanked', package.versions.find_by!(number: number).status }
    end
  end

  %w[homebrew clojars].each do |ecosystem|
    test "#{ecosystem} sync keeps two-component releases eligible" do
      registry = Registry.create!(name: "#{ecosystem}.example", url: "https://#{ecosystem}.example", ecosystem: ecosystem)
      package = registry.packages.create!(name: 'widget', ecosystem: ecosystem)
      package.versions.create!(number: '1.0.0', registry: registry, published_at: 1.year.ago)
      backend = registry.ecosystem_instance
      backend.stubs(:package_metadata).with('widget').returns(name: 'widget', versions: ['2.0'])
      backend.stubs(:versions_metadata).returns([{ number: '2.0', published_at: 1.day.ago }])
      backend.stubs(:dependencies_metadata).returns([])
      registry.stubs(:sync_maintainers)
      Package.any_instance.stubs(:check_status)

      registry.sync_package('widget')

      assert_equal '2.0', package.reload.latest_release_number
      assert_equal ['2.0'], package.versions.where(latest: true).pluck(:number)
    end
  end
end
