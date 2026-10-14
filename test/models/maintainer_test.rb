require "test_helper"

class MaintainerTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:registry)
    should have_many(:maintainerships)
    should have_many(:packages).through(:maintainerships)
  end

  setup do
    @registry = Registry.create!(name: 'registry.example', url: 'https://registry.example', ecosystem: 'example')
  end

  test 'matching_identity matches login and uuid case-insensitively' do
    by_login = @registry.maintainers.create!(uuid: 'uuid-1', login: 'SomeUser')
    by_uuid = @registry.maintainers.create!(uuid: 'OtherUser', login: 'different-login')

    assert_equal [by_login, by_uuid].sort, @registry.maintainers.matching_identity(['someuser', 'otheruser']).sort
  end

  test 'hide retains identifiers and removes personal details and package associations' do
    maintainer = @registry.maintainers.create!(
      uuid: 'uuid-1',
      login: 'someuser',
      name: 'Some User',
      email: 'some@example.com',
      url: 'https://example.com/someuser',
      organization: false,
      packages_count: 1,
      total_downloads: 10
    )
    package = @registry.packages.create!(name: 'some-package', ecosystem: @registry.ecosystem, maintainers_count: 1)
    package.maintainerships.create!(maintainer: maintainer)

    maintainer.hide!

    maintainer.reload
    assert maintainer.hidden?
    assert_equal 'uuid-1', maintainer.uuid
    assert_equal 'someuser', maintainer.login
    assert_nil maintainer.name
    assert_nil maintainer.email
    assert_nil maintainer.url
    assert_nil maintainer.organization
    assert_equal Maintainer::TOMBSTONE_PACKAGES_COUNT, maintainer.packages_count
    assert_equal 0, maintainer.total_downloads
    assert_empty maintainer.maintainerships
    assert_equal 0, package.reload.maintainers_count
  end
end
