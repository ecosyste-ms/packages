require 'test_helper'
require 'rake'

class ExportsRakeTest < ActiveSupport::TestCase
  setup do
    if Rake::Task.tasks.empty?
      silence_warnings do
        Packages::Application.load_tasks
      end
    end
  end

  teardown do
    ENV.delete('REGISTRY')
  end

  test "integrity_worklist outputs jsonl for versions missing integrity" do
    registry = Registry.create(name: 'hackage.haskell.org', url: 'https://hackage.haskell.org', ecosystem: 'hackage')
    package = Package.create(name: 'aeson', ecosystem: 'hackage', registry: registry)
    Version.create(package: package, number: '2.2.3.0', registry: registry)
    Version.create(package: package, number: '2.2.2.0', registry: registry, integrity: 'sha256-abc123')

    ENV['REGISTRY'] = 'hackage.haskell.org'
    output = capture_io { Rake::Task["exports:integrity_worklist"].execute }.first

    lines = output.split("\n").map { |line| JSON.parse(line) }
    assert_equal 1, lines.length
    assert_equal({
      'registry' => 'hackage.haskell.org',
      'name' => 'aeson',
      'version' => '2.2.3.0',
      'url' => 'https://hackage.haskell.org/package/aeson-2.2.3.0/aeson-2.2.3.0.tar.gz'
    }, lines.first)
  end

  test "integrity_worklist skips versions without a download url" do
    registry = Registry.create(name: 'artifacthub.io', url: 'https://artifacthub.io', ecosystem: 'helm')
    package = Package.create(name: 'bitnami/redis', ecosystem: 'helm', registry: registry)
    Version.create(package: package, number: '1.0.0', registry: registry)

    ENV['REGISTRY'] = 'artifacthub.io'
    output = capture_io { Rake::Task["exports:integrity_worklist"].execute }.first

    assert_equal '', output
  end

  test "integrity_worklist exits when registry not found" do
    ENV['REGISTRY'] = 'nope'
    assert_raises(SystemExit) do
      capture_io { Rake::Task["exports:integrity_worklist"].execute }
    end
  end
end
