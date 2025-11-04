require "test_helper"

class BaseTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create(name: 'Test Registry', url: 'https://test.example.com', ecosystem: 'test')
    @ecosystem = Ecosystem::Base.new(@registry)
    @package = @registry.packages.create(ecosystem: 'test', name: 'test-package')
  end

  test 'check_status returns nil when URL is blank' do
    @package.update(repository_url: nil, homepage: nil)
    status = @ecosystem.check_status(@package)
    assert_nil status
  end

  test 'check_status returns nil when URL is invalid' do
    # Create a package with an invalid URI in repository_url
    invalid_package = @registry.packages.create(
      ecosystem: 'test',
      name: 'invalid-uri-package',
      repository_url: 'https://MTAnalytics (#11070)'
    )

    # Mock check_status_url to return the invalid URL
    @ecosystem.stubs(:check_status_url).returns('https://MTAnalytics (#11070)')
    status = @ecosystem.check_status(invalid_package)
    assert_nil status
  end

  test 'check_status returns removed for 404 status' do
    stub_request(:head, "https://example.com/package")
      .to_return(status: 404)

    @ecosystem.stubs(:check_status_url).returns('https://example.com/package')
    status = @ecosystem.check_status(@package)
    assert_equal 'removed', status
  end

  test 'check_status returns removed for 410 status' do
    stub_request(:head, "https://example.com/package")
      .to_return(status: 410)

    @ecosystem.stubs(:check_status_url).returns('https://example.com/package')
    status = @ecosystem.check_status(@package)
    assert_equal 'removed', status
  end

  test 'check_status returns nil for 200 status' do
    stub_request(:head, "https://example.com/package")
      .to_return(status: 200)

    @ecosystem.stubs(:check_status_url).returns('https://example.com/package')
    status = @ecosystem.check_status(@package)
    assert_nil status
  end

  test 'check_status handles Faraday errors gracefully' do
    stub_request(:head, "https://example.com/package")
      .to_raise(Faraday::ConnectionFailed.new('Connection failed'))

    @ecosystem.stubs(:check_status_url).returns('https://example.com/package')
    status = @ecosystem.check_status(@package)
    assert_nil status
  end
end
