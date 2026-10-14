require "test_helper"
require "rake"

class TakedownRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("takedown:hide_user")
    @registry = Registry.create!(name: 'packagist.org', url: 'https://packagist.org', ecosystem: 'packagist')
    @maintainer = @registry.maintainers.create!(
      uuid: 'leo-unglaub',
      login: 'Leo-Unglaub',
      name: 'Leo Unglaub',
      email: 'leo@example.com',
      packages_count: 1,
      total_downloads: 10
    )
    @other_maintainer = @registry.maintainers.create!(uuid: 'other', login: 'other')
    @package = @registry.packages.create!(name: 'leo-unglaub/package', ecosystem: @registry.ecosystem, maintainers_count: 2)
    @package.maintainerships.create!(maintainer: @maintainer)
    @package.maintainerships.create!(maintainer: @other_maintainer)
  end

  teardown do
    ENV.delete('LOGIN')
    ENV.delete('REGISTRY')
  end

  test 'hide_user tombstones the maintainer and removes only their package associations' do
    other_registry = Registry.create!(name: 'npmjs.org', url: 'https://npmjs.org', ecosystem: 'npm')
    same_login = other_registry.maintainers.create!(uuid: 'leo-unglaub', login: 'leo-unglaub')
    ENV['LOGIN'] = 'leo-unglaub'
    ENV['REGISTRY'] = 'PACKAGIST.ORG'

    output, = capture_io { Rake::Task["takedown:hide_user"].execute }

    assert @maintainer.reload.hidden?
    assert_nil @maintainer.name
    assert_nil @maintainer.email
    assert_equal [@other_maintainer], @package.reload.maintainers.to_a
    assert_equal 1, @package.maintainers_count
    assert_not same_login.reload.hidden?
    assert_includes output, '[packages] hidden 1 maintainer record(s) for packagist.org/leo-unglaub'
    assert_includes output, '[packages] removed 1 package association(s) for packagist.org/leo-unglaub'
  end

  test 'hide_user creates a hidden tombstone when no maintainer exists' do
    ENV['LOGIN'] = 'new-user'
    ENV['REGISTRY'] = @registry.name

    capture_io { Rake::Task["takedown:hide_user"].execute }

    maintainer = @registry.maintainers.matching_identity('new-user').first
    assert maintainer.hidden?
    assert_equal 'new-user', maintainer.uuid
    assert_equal 'new-user', maintainer.login
  end

  test 'report includes maintainer visibility and package counts' do
    ENV['LOGIN'] = @maintainer.login
    ENV['REGISTRY'] = @registry.name

    output, = capture_io { Rake::Task["takedown:report"].execute }

    assert_includes output, '[packages] packagist.org/Leo-Unglaub: hidden=0 visible=1 packages=1'
  end

  test 'hide_user aborts without a login' do
    ENV['REGISTRY'] = @registry.name

    assert_raises(SystemExit) do
      capture_io { Rake::Task["takedown:hide_user"].execute }
    end
  end

  test 'hide_user aborts without a registry' do
    ENV['LOGIN'] = @maintainer.login

    assert_raises(SystemExit) do
      capture_io { Rake::Task["takedown:hide_user"].execute }
    end
  end
end
