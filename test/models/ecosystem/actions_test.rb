require "test_helper"

class ActionsTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create(name: 'github actions', url: 'https://actions.io', ecosystem: 'actions')
    @ecosystem = Ecosystem::Actions.new(@registry)
    @package = @registry.packages.create(ecosystem: 'actions', name: 'getsentry/action-git-diff-suggestions', repository_url: "https://github.com/getsentry/action-git-diff-suggestions")
    @version = @package.versions.create(number: 'v1', metadata: {download_url:"https://codeload.github.com/getsentry/action-git-diff-suggestions/tar.gz/refs/v1"})
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, "https://github.com/getsentry/action-git-diff-suggestions"
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, 'v1')
    assert_equal registry_url, "https://github.com/getsentry/action-git-diff-suggestions"
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://codeload.github.com/getsentry/action-git-diff-suggestions/tar.gz/refs/v1"
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_nil documentation_url
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, 'v1')
    assert_nil documentation_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_nil install_command
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, 'v1')
    assert_nil install_command
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://github.com/getsentry/action-git-diff-suggestions"
  end

  test 'all_package_names' do
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/package_names/actions")
      .to_return({ status: 200, body: file_fixture('actions/actions') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 612
    assert_equal all_package_names.last, 'Ynniss/golang-security-action'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/package_names/actions")
      .to_return({ status: 200, body: file_fixture('actions/actions') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 20
    assert_equal recently_updated_package_names.last, 'cds-snc/github-repository-metadata-exporter'
  end
  
  test 'package_metadata' do
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://github.com/getsentry/action-git-diff-suggestions")
      .to_return({ status: 200, body: file_fixture('actions/lookup?url=https:%2F%2Fgithub.com%2Fgetsentry%2Faction-git-diff-suggestions') })
    stub_request(:get, "https://raw.githubusercontent.com/getsentry/action-git-diff-suggestions/main/action.yml")
      .to_return({ status: 200, body: file_fixture('actions/action.yml') })
    stub_request(:get, "http://repos.ecosyste.ms/api/v1/hosts/GitHub/repositories/getsentry%2Faction-git-diff-suggestions/tags?per_page=1000")
      .to_return({ status: 200, body: file_fixture('actions/tags') })
    stub_request(:get, "https://raw.githubusercontent.com/getsentry/action-git-diff-suggestions/v1/action.yml")
      .to_return({ status: 200, body: file_fixture('actions/action.yml.1') })
    
    package_metadata = @ecosystem.package_metadata('getsentry/action-git-diff-suggestions')

    assert_equal package_metadata, {
      :name=>"getsentry/action-git-diff-suggestions", 
      :description=>"This GitHub Action will take the current git changes and apply them as GitHub code review suggestions", 
      :repository_url=>"https://github.com/getsentry/action-git-diff-suggestions", 
      :licenses=>"mit", 
      :keywords_array=>[], 
      :homepage=>nil, 
      :tags_url=>"http://repos.ecosyste.ms/api/v1/hosts/GitHub/repositories/getsentry%2Faction-git-diff-suggestions/tags", 
      :namespace=>"getsentry", 
      :metadata=>{"name"=>"action-git-diff-suggestions", "description"=>"This GitHub Action will take the current git changes and apply them as GitHub code review suggestions", "author"=>"Sentry", "branding"=>{"icon"=>"book-open", "color"=>"purple"}, "inputs"=>{"github-token"=>{"description"=>"github token"}, "message"=>{"description"=>"The message to prepend the review suggestion"}}, "runs"=>{"using"=>"node12", "main"=>"dist/index.js"}, "default_branch"=>"main", "path"=>nil}}
  end

  test 'versions_metadata' do
    stub_request(:get, "http://repos.ecosyste.ms/api/v1/hosts/GitHub/repositories/getsentry%2Faction-git-diff-suggestions/tags?per_page=1000")
      .to_return({ status: 200, body: file_fixture('actions/tags') })
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://github.com/getsentry/action-git-diff-suggestions")
      .to_return({ status: 200, body: file_fixture('actions/lookup?url=https:%2F%2Fgithub.com%2Fgetsentry%2Faction-git-diff-suggestions') })
    stub_request(:get, "https://raw.githubusercontent.com/getsentry/action-git-diff-suggestions/main/action.yml")
      .to_return({ status: 200, body: file_fixture('actions/action.yml') })
    stub_request(:get, "https://raw.githubusercontent.com/getsentry/action-git-diff-suggestions/v1/action.yml")
      .to_return({ status: 200, body: file_fixture('actions/action.yml.1') })
    package_metadata = @ecosystem.package_metadata('getsentry/action-git-diff-suggestions')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata.first, {:number=>"v1", :published_at=>"2020-11-25T01:40:25.000Z", :metadata=>{:sha=>"8c75946d0d7bbe80a92cf3579d544321512c30b7", :download_url=>"https://codeload.github.com/getsentry/action-git-diff-suggestions/tar.gz/v1"}}
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:githubactions/getsentry/action-git-diff-suggestions'
    assert PackageURL.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:githubactions/getsentry/action-git-diff-suggestions@v1'
    assert PackageURL.parse(purl)
  end
end
