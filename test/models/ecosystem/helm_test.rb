require "test_helper"

class HelmTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Artifact Hub', url: 'https://artifacthub.io', ecosystem: 'helm', default: true)
    @ecosystem = Ecosystem::Helm.new(@registry)
    @package = Package.new(
      ecosystem: 'helm',
      name: 'prometheus-community/kube-prometheus-stack',
      namespace: 'prometheus-community',
      metadata: { 'repository_url' => 'https://prometheus-community.github.io/helm-charts' }
    )
    @version = @package.versions.build(number: '74.0.0')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack/74.0.0'
  end

  test 'registry_url with invalid name format' do
    @package.name = 'invalid-name'
    assert_nil @ecosystem.registry_url(@package)
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_nil download_url
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, 'https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 74.0.0'
  end

  test 'install_command without repo url' do
    @package.metadata = {}
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack'
  end

  test 'install_command with invalid name format' do
    @package.name = 'invalid-name'
    install_command = @ecosystem.install_command(@package)
    assert_nil install_command
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, 'https://artifacthub.io/api/v1/packages/helm/prometheus-community/kube-prometheus-stack'
  end

  test 'check_status_url with invalid name format' do
    @package.name = 'invalid-name'
    check_status_url = @ecosystem.check_status_url(@package)
    assert_nil check_status_url
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:helm/prometheus-community/kube-prometheus-stack'
    assert Purl::PackageURL.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:helm/prometheus-community/kube-prometheus-stack@74.0.0'
    assert Purl::PackageURL.parse(purl)
  end

  test 'purl with invalid name format' do
    @package.name = 'invalid-name'
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:helm/invalid-name'
  end

  test 'purl_type' do
    assert_equal @ecosystem.class.purl_type, 'helm'
  end

  test 'all_package_names' do
    stub_request(:get, "https://artifacthub.io/api/v1/helm-exporter")
      .to_return({ status: 200, body: file_fixture('helm/helm-exporter') })

    all_package_names = @ecosystem.all_package_names
    assert_kind_of Array, all_package_names
    assert all_package_names.any?
    all_package_names.each do |name|
      assert_match /\w+\/\w+/, name
    end
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://artifacthub.io/api/v1/packages/search?kind=0&sort=last_updated&limit=60")
      .to_return({ status: 200, body: file_fixture('helm/search-results') })

    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_kind_of Array, recently_updated_package_names
    assert recently_updated_package_names.any?
  end

  test 'package_metadata' do
    stub_request(:get, "https://artifacthub.io/api/v1/packages/helm/prometheus-community/kube-prometheus-stack")
      .to_return({ status: 200, body: file_fixture('helm/prometheus-community-kube-prometheus-stack') })

    package_metadata = @ecosystem.package_metadata('prometheus-community/kube-prometheus-stack')

    assert_equal package_metadata[:name], "prometheus-community/kube-prometheus-stack"
    assert package_metadata[:description].present?
    assert_equal package_metadata[:namespace], "prometheus-community"
    assert_kind_of Array, package_metadata[:keywords_array]
    assert_equal package_metadata[:downloads], 0
    assert_equal package_metadata[:downloads_period], "total"
    assert package_metadata[:metadata]['app_version'].present?
    assert package_metadata[:metadata]['chart_version'].present?
    assert package_metadata[:metadata]['repository_url'].present?
  end

  test 'package_metadata with invalid name format' do
    package_metadata = @ecosystem.package_metadata('invalid-name')
    assert_equal package_metadata, false
  end

  test 'versions_metadata' do
    stub_request(:get, "https://artifacthub.io/api/v1/packages/helm/prometheus-community/kube-prometheus-stack")
      .to_return({ status: 200, body: file_fixture('helm/prometheus-community-kube-prometheus-stack') })

    package_metadata = @ecosystem.package_metadata('prometheus-community/kube-prometheus-stack')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_kind_of Array, versions_metadata

    if versions_metadata.any?
      first_version = versions_metadata.first
      assert first_version[:number].present?
      assert_equal first_version[:licenses], package_metadata[:licenses]
      assert_kind_of Hash, first_version[:metadata]
    end
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://artifacthub.io/api/v1/packages/helm/prometheus-community/kube-prometheus-stack/74.0.0")
      .to_return({ status: 200, body: file_fixture('helm/prometheus-community-kube-prometheus-stack-74.0.0') })

    deps = @ecosystem.dependencies_metadata('prometheus-community/kube-prometheus-stack', '74.0.0', {})

    assert_kind_of Array, deps
    assert deps.any?

    named_dep = deps.find { |d| d[:package_name] == 'prometheus-community/kube-state-metrics' }
    assert named_dep
    assert_equal 'runtime', named_dep[:kind]
    assert_equal 'helm', named_dep[:ecosystem]
    assert named_dep[:requirements].present?

    # Deps without artifacthub_repository_name use just the name
    crds_dep = deps.find { |d| d[:package_name] == 'crds' }
    assert crds_dep
  end

  test 'dependencies_metadata with invalid name format' do
    deps = @ecosystem.dependencies_metadata('invalid-name', '1.0.0', {})
    assert_equal [], deps
  end

  test 'check_status with valid package' do
    stub_request(:get, "https://artifacthub.io/api/v1/packages/helm/prometheus-community/kube-prometheus-stack")
      .to_return({ status: 200 })

    status = @ecosystem.check_status(@package)
    assert_nil status
  end

  test 'check_status with removed package' do
    stub_request(:get, "https://artifacthub.io/api/v1/packages/helm/prometheus-community/kube-prometheus-stack")
      .to_return({ status: 404 })

    status = @ecosystem.check_status(@package)
    assert_equal "removed", status
  end

  test 'check_status with invalid name format' do
    @package.name = 'invalid-name'
    status = @ecosystem.check_status(@package)
    assert_nil status
  end
end
