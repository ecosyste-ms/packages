require "test_helper"

class DockerTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: "Amazon ECR Public", url: "https://gallery.ecr.aws", ecosystem: "docker", default: false)
    @ecosystem = Ecosystem::Docker.new(@registry)
    @package = Package.new(ecosystem: "docker", name: "docker/library/busybox", namespace: "docker")
    @version = @package.versions.build(number: "latest", metadata: { "images" => [{ "digest" => "sha256:abc" }] })
  end

  test "amazon ecr public registry_url" do
    assert_equal "https://gallery.ecr.aws/docker/library/busybox", @ecosystem.registry_url(@package)
  end

  test "amazon ecr public install_command" do
    assert_equal "docker pull public.ecr.aws/docker/library/busybox", @ecosystem.install_command(@package)
    assert_equal "docker pull public.ecr.aws/docker/library/busybox:latest", @ecosystem.install_command(@package, "latest")
  end

  test "amazon ecr public package_metadata" do
    stub_request(:post, "https://api.us-east-1.gallery.ecr.aws/getRepositoryCatalogData")
      .with(body: { registryAliasName: "docker", repositoryName: "library/busybox" }.to_json)
      .to_return(
        status: 200,
        body: {
          catalogData: {
            description: "Busybox base image",
            sourceCodeRepository: "https://github.com/docker-library/busybox",
            downloadCount: 123,
            architectures: ["x86-64"],
            operatingSystems: ["Linux"]
          },
          registryAliasName: "docker",
          repositoryName: "library/busybox"
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    metadata = @ecosystem.package_metadata("docker/library/busybox")

    assert_equal "docker/library/busybox", metadata[:name]
    assert_equal "Busybox base image", metadata[:description]
    assert_equal "docker", metadata[:namespace]
    assert_equal 123, metadata[:downloads]
    assert_equal "total", metadata[:downloads_period]
    assert_equal "https://github.com/docker-library/busybox", metadata[:repository_url]
  end

  test "amazon ecr public versions_metadata" do
    stub_request(:post, "https://api.us-east-1.gallery.ecr.aws/describeImageTags")
      .with(body: { registryAliasName: "docker", repositoryName: "library/busybox", maxResults: 100 }.to_json)
      .to_return(
        status: 200,
        body: {
          imageTagDetails: [
            {
              imageTag: "1.36.0",
              createdAt: "2023-05-12T03:22:40.827Z",
              imageDetail: {
                imageDigest: "sha256:abc",
                imageSizeInBytes: 2_592_208
              }
            }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    versions = @ecosystem.versions_metadata({ name: "docker/library/busybox" })

    assert_equal 1, versions.length
    assert_equal "1.36.0", versions.first[:number]
    assert_equal "2023-05-12T03:22:40.827Z", versions.first[:published_at]
    assert_equal "sha256:abc", versions.first[:metadata]["imageDetail"]["imageDigest"]
  end

  test "amazon ecr public all_package_names" do
    stub_request(:post, "https://api.us-east-1.gallery.ecr.aws/searchRepositoryCatalogData")
      .with(body: { maxResults: 100 }.to_json)
      .to_return(
        status: 200,
        body: {
          repositoryCatalogSearchResultList: [
            { primaryRegistryAliasName: "docker", repositoryName: "library/busybox" },
            { primaryRegistryAliasName: "public", repositoryName: "eks/aws-load-balancer-controller" }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_equal ["docker/library/busybox", "public/eks/aws-load-balancer-controller"], @ecosystem.all_package_names
  end
end
