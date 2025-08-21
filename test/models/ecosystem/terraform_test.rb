require "test_helper"

class TerraformTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Terraform Registry', url: 'https://registry.terraform.io', ecosystem: 'terraform')
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

  test 'registry_url without namespace' do
    @package.namespace = nil
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws'
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

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_equal documentation_url, 'https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'terraform init # with module "example" { source = "terraform-aws-modules/vpc/aws" }'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'terraform init # with module "example" { source = "terraform-aws-modules/vpc/aws?version=5.0.0" }'
  end

  test 'install_command with invalid name format' do
    @package.name = 'invalid-name'
    install_command = @ecosystem.install_command(@package)
    assert_nil install_command
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, 'https://registry.terraform.io/v1/modules/terraform-aws-modules/vpc/aws/versions'
  end

  test 'check_status_url with invalid name format' do
    @package.name = 'invalid-name'
    check_status_url = @ecosystem.check_status_url(@package)
    assert_nil check_status_url
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:terraform/terraform-aws-modules/aws/vpc'
    assert PackageURL.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:terraform/terraform-aws-modules/aws/vpc@5.0.0'
    assert PackageURL.parse(purl)
  end

  test 'purl with invalid name format' do
    @package.name = 'invalid-name'
    purl = @ecosystem.purl(@package)
    assert_nil purl
  end

  test 'purl_type' do
    assert_equal @ecosystem.class.purl_type, 'terraform'
  end

  test 'all_package_names' do
    stub_request(:get, "https://registry.terraform.io/v2/modules?page[size]=100&page[number]=1")
      .to_return({ status: 200, body: file_fixture('terraform/v2-search') })
    
    # Stub the second request to return empty to end pagination
    stub_request(:get, "https://registry.terraform.io/v2/modules?page[size]=100&page[number]=2")
      .to_return({ status: 200, body: '{"data": []}' })
    
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 2
    assert_includes all_package_names, 'terraform-aws-modules/vpc/aws'
    assert_includes all_package_names, 'hashicorp/consul/aws'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://registry.terraform.io/v2/modules?include=latest-version&page[size]=100&page[number]=1&sort=-updated")
      .to_return({ status: 200, body: file_fixture('terraform/v2-search') })
    
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
    assert_equal package_metadata[:description], "Terraform module which creates VPC resources on AWS"
    assert_equal package_metadata[:homepage], "https://github.com/terraform-aws-modules/terraform-aws-vpc"
    assert_equal package_metadata[:licenses], "Unknown"
    assert_equal package_metadata[:repository_url], "https://github.com/terraform-aws-modules/terraform-aws-vpc"
    assert_equal package_metadata[:keywords_array], []
    assert_equal package_metadata[:namespace], "terraform-aws-modules"
    assert_equal package_metadata[:downloads], 1500000
    assert_equal package_metadata[:downloads_period], "total"
    assert_equal package_metadata[:metadata]['provider'], "aws"
    assert_equal package_metadata[:metadata]['verified'], true
    assert_equal package_metadata[:metadata]['trusted'], true
    assert_equal package_metadata[:metadata]['latest_version'], "5.0.0"
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
    
    assert_equal 2, versions_metadata.length
    
    first_version = versions_metadata.first
    assert_equal first_version[:number], "5.0.0"
    assert_equal first_version[:published_at], "2023-06-02T14:30:00Z"
    assert_equal first_version[:licenses], "Unknown"
    assert_equal first_version[:metadata]['providers'], ["aws"]
    assert_equal first_version[:metadata]['submodules'].first['name'], "complete-sg"
  end

  test 'check_status with valid module' do
    stub_request(:get, "https://registry.terraform.io/v1/modules/terraform-aws-modules/vpc/aws/versions")
      .to_return({ status: 200, body: file_fixture('terraform/terraform-aws-modules-vpc-aws-versions') })
    
    status = @ecosystem.check_status(@package)
    assert_nil status
  end

  test 'check_status with removed module' do
    stub_request(:get, "https://registry.terraform.io/v1/modules/terraform-aws-modules/vpc/aws/versions")
      .to_return({ status: 404 })
    
    status = @ecosystem.check_status(@package)
    assert_equal status, "removed"
  end

  test 'check_status with empty versions' do
    stub_request(:get, "https://registry.terraform.io/v1/modules/terraform-aws-modules/vpc/aws/versions")
      .to_return({ status: 200, body: '{"modules": [{"versions": []}]}' })
    
    status = @ecosystem.check_status(@package)
    assert_equal status, "removed"
  end

  test 'check_status with invalid name format' do
    @package.name = 'invalid-name'
    status = @ecosystem.check_status(@package)
    assert_nil status
  end

end