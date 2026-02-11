require "test_helper"

class TerraformTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Terraform Registry', url: 'https://registry.terraform.io', ecosystem: 'terraform', default: true)
    @ecosystem = Ecosystem::Terraform.new(@registry)
    @package = Package.new(
      ecosystem: 'terraform',
      name: 'terraform-aws-modules/vpc/aws',
      namespace: 'terraform-aws-modules',
      metadata: { 'provider' => 'aws' }
    )
    @version = @package.versions.build(number: '5.0.0')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/5.0.0'
  end

  test 'registry_url with invalid name format' do
    @package.name = 'invalid-name'
    assert_nil @ecosystem.registry_url(@package)
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://registry.terraform.io/v1/modules/terraform-aws-modules/vpc/aws/5.0.0/download'
  end

  test 'download_url without version' do
    download_url = @ecosystem.download_url(@package, nil)
    assert_nil download_url
  end

  test 'download_url with invalid name format' do
    @package.name = 'invalid-name'
    download_url = @ecosystem.download_url(@package, @version)
    assert_nil download_url
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, 'https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_includes install_command, 'source  = "terraform-aws-modules/vpc/aws"'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_includes install_command, 'source  = "terraform-aws-modules/vpc/aws"'
    assert_includes install_command, 'version = "5.0.0"'
  end

  test 'install_command with invalid name format' do
    @package.name = 'invalid-name'
    install_command = @ecosystem.install_command(@package)
    assert_nil install_command
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, 'https://registry.terraform.io/v1/modules/terraform-aws-modules/vpc/aws'
  end

  test 'check_status_url with invalid name format' do
    @package.name = 'invalid-name'
    check_status_url = @ecosystem.check_status_url(@package)
    assert_nil check_status_url
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:terraform/terraform-aws-modules/aws/vpc'
    assert Purl::PackageURL.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:terraform/terraform-aws-modules/aws/vpc@5.0.0'
    assert Purl::PackageURL.parse(purl)
  end

  test 'purl with invalid name format' do
    @package.name = 'invalid-name'
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:terraform/invalid-name'
  end

  test 'purl_type' do
    assert_equal @ecosystem.class.purl_type, 'terraform'
  end

  test 'all_package_names' do
    stub_request(:get, "https://registry.terraform.io/v2/modules?page%5Bsize%5D=100&page%5Bnumber%5D=1")
      .to_return({ status: 200, body: file_fixture('terraform/v2-search') })

    stub_request(:get, "https://registry.terraform.io/v2/modules?page%5Bsize%5D=100&page%5Bnumber%5D=2")
      .to_return({ status: 200, body: '{"data": []}' })

    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 2
    assert_includes all_package_names, 'terraform-aws-modules/vpc/aws'
    assert_includes all_package_names, 'hashicorp/consul/aws'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://registry.terraform.io/v1/modules?limit=100&offset=0")
      .to_return({ status: 200, body: '{"modules": [{"id": "terraform-aws-modules/vpc/aws/6.6.0"}, {"id": "hashicorp/consul/aws/0.12.0"}]}' })

    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 2
    assert_includes recently_updated_package_names, 'terraform-aws-modules/vpc/aws'
    assert_includes recently_updated_package_names, 'hashicorp/consul/aws'
  end

  test 'package_metadata' do
    stub_request(:get, "https://registry.terraform.io/v1/modules/terraform-aws-modules/vpc/aws")
      .to_return({ status: 200, body: file_fixture('terraform/terraform-aws-modules-vpc-aws') })

    package_metadata = @ecosystem.package_metadata('terraform-aws-modules/vpc/aws')

    assert_equal package_metadata[:name], "terraform-aws-modules/vpc/aws"
    assert package_metadata[:description].present?
    assert_equal package_metadata[:repository_url], "https://github.com/terraform-aws-modules/terraform-aws-vpc"
    assert_equal package_metadata[:licenses], "Unknown"
    assert_equal package_metadata[:namespace], "terraform-aws-modules"
    assert_equal package_metadata[:downloads], 164832241
    assert_equal package_metadata[:downloads_period], "total"
    assert_equal package_metadata[:metadata]['provider'], "aws"
  end

  test 'package_metadata with invalid name format' do
    package_metadata = @ecosystem.package_metadata('invalid-name')
    assert_equal package_metadata, false
  end

  test 'versions_metadata' do
    stub_request(:get, "https://registry.terraform.io/v1/modules/terraform-aws-modules/vpc/aws")
      .to_return({ status: 200, body: file_fixture('terraform/terraform-aws-modules-vpc-aws') })

    package_metadata = @ecosystem.package_metadata('terraform-aws-modules/vpc/aws')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal 3, versions_metadata.length
    assert_equal "1.0.0", versions_metadata.first[:number]
    assert_equal "Unknown", versions_metadata.first[:licenses]
  end

  test 'check_status with valid module' do
    stub_request(:get, "https://registry.terraform.io/v1/modules/terraform-aws-modules/vpc/aws")
      .to_return({ status: 200 })

    status = @ecosystem.check_status(@package)
    assert_nil status
  end

  test 'check_status with removed module' do
    stub_request(:get, "https://registry.terraform.io/v1/modules/terraform-aws-modules/vpc/aws")
      .to_return({ status: 404 })

    status = @ecosystem.check_status(@package)
    assert_equal "removed", status
  end

  test 'check_status with invalid name format' do
    @package.name = 'invalid-name'
    status = @ecosystem.check_status(@package)
    assert_nil status
  end

  test 'check_status reuses memoized metadata without extra HTTP request' do
    stub_request(:get, "https://registry.terraform.io/v1/modules/terraform-aws-modules/vpc/aws")
      .to_return({ status: 200, body: file_fixture('terraform/terraform-aws-modules-vpc-aws') })

    # Fetch metadata first to populate the cache
    @ecosystem.package_metadata('terraform-aws-modules/vpc/aws')

    # check_status should reuse cached data
    status = @ecosystem.check_status(@package)
    assert_nil status

    # The API should only have been called once (for the initial fetch)
    assert_requested(:get, "https://registry.terraform.io/v1/modules/terraform-aws-modules/vpc/aws", times: 1)
  end
end
