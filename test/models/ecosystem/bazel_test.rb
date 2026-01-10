require "test_helper"

class BazelTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'Registry.bazel.build', url: 'https://registry.bazel.build', ecosystem: 'Bazel')
    @ecosystem = Ecosystem::Bazel.new(@registry)
    @package = Package.new(ecosystem: 'Bazel', name: 'rules_go')
    @version = @package.versions.build(number: '0.59.0', metadata: {url: "https://github.com/bazel-contrib/rules_go/releases/download/v0.59.0/rules_go-v0.59.0.zip"})
    @maintainer = @registry.maintainers.build(login: 'foo')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://registry.bazel.build/modules/rules_go'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://registry.bazel.build/modules/rules_go/0.59.0'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, "bazel_dep(name = \"rules_go\")"
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, "bazel_dep(name = \"rules_go\", version = \"0.59.0\")"
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://github.com/bazel-contrib/rules_go/releases/download/v0.59.0/rules_go-v0.59.0.zip"
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, "https://registry.bazel.build/docs/rules_go"
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_equal documentation_url, "https://registry.bazel.build/docs/rules_go/0.59.0"
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://registry.bazel.build/modules/rules_go"
  end

  test 'all_package_names' do
    stub_request(:get, "https://api.github.com/repos/bazelbuild/bazel-central-registry/git/trees/main")
      .to_return({ status: 200, body: file_fixture('bazel/github_root_tree') })
    # Update this variable in case of the fixture update
    modules_tree_sha = "e5e9debb664a3bd1d7047f4395caacca16be4457"
    stub_request(:get, "https://api.github.com/repos/bazelbuild/bazel-central-registry/git/trees/#{modules_tree_sha}")
      .to_return({ status: 200, body: file_fixture('bazel/github_modules_tree') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 953
    assert_equal all_package_names.last, 'zsync3'
  end

  test 'recently_updated_package_names' do
    assert_equal @ecosystem.recently_updated_package_names, []
  end

  test 'package_metadata' do
    stub_request(:get, "https://bcr.bazel.build/modules/rules_go/metadata.json")
      .to_return({ status: 200, body: file_fixture('bazel/rules_go_package_metadata') })
    package_metadata = @ecosystem.package_metadata('rules_go')

    assert_equal package_metadata[:name], "rules_go"
    assert_equal package_metadata[:homepage], "https://github.com/bazelbuild/rules_go"
    assert_equal package_metadata[:repository_url], "https://github.com/bazelbuild/rules_go"
    assert_equal package_metadata[:versions], [
      "0.37.0",
      "0.59.0"
    ]
    assert_equal package_metadata[:metadata],
      {
        maintainers: [
          {
            "email" => "fabian@meumertzhe.im",
            "github" => "fmeum",
            "name" => "Fabian Meumertzheim",
            "github_user_id" => 4312191
          },
          {
            "email" => "zplin@uber.com",
            "github" => "linzhp",
            "name" => "Zhongpeng Lin",
            "github_user_id" => 98395
          },
          {
            "email" => "tfrench@uber.com",
            "github" => "tyler-french",
            "name" => "Tyler French",
            "github_user_id" => 66684063
          }
        ],
        yanked_versions: {
          "0.37.0" => "Obsolete experimental version that emits debug prints. Update to 0.39.1 or higher"
        },
        deprecated: nil,
        repository: ["github:bazel-contrib/rules_go"]
      }
  end

  test 'versions_metadata' do
    @package = Package.new(ecosystem: 'Bazel', name: 'pico-sdk')
    @version = @package.versions.build(number: '2.1.1-develop.bcr.20250113-4b6e6475')
    stub_request(:get, "https://bcr.bazel.build/modules/pico-sdk/metadata.json")
      .to_return({ status: 200, body: file_fixture('bazel/pico_sdk_package_metadata') })
    stub_request(:get, "https://bcr.bazel.build/modules/pico-sdk/2.2.0/source.json")
      .to_return({ status: 200, body: file_fixture('bazel/pico_sdk_package_version_metadata1') })
    stub_request(:get, "https://bcr.bazel.build/modules/pico-sdk/2.2.1-develop.bcr.20250915-8fcd44a1/source.json")
      .to_return({ status: 200, body: file_fixture('bazel/pico_sdk_package_version_metadata2') })
    package_metadata = @ecosystem.package_metadata('pico-sdk')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {
        number: "2.2.0",
        status: nil,
        integrity: "sha256-Jnj+Kxds9kp/cc2RdJ/fkTTIz3/4S3GZ3+XqDW26b6Q=",
        metadata: {
          type: "archive",
          patch_strip: nil,
          patches: nil,
          strip_prefix: "pico-sdk-2.2.0",
          url: "https://github.com/raspberrypi/pico-sdk/releases/download/2.2.0/pico-sdk-2.2.0.tar.gz",
          mirror_urls: nil,
          overlay: nil,
          archive_type: nil
        }
      },
      {
        number: "2.2.1-develop.bcr.20250915-8fcd44a1",
        status: nil,
        integrity: nil,
        metadata: {
          type: "git_repository",
          patch_strip: 1,
          patches: { "0001-Patch-version-string.patch" => "sha256-O4aYyU1INnDA+pv0Iw1ogAvUIUOONDpZ6Mdpr6PhQnw="},
          strip_prefix: nil,
          remote: "https://github.com/raspberrypi/pico-sdk.git",
          commit: "8fcd44a1718337861214ba5499a8faceea2bfa1d",
          shallow_since: nil,
          tag: nil,
          init_submodules: nil,
          verbose: nil
        }
      }
    ]
  end

  test 'versions_metadata for package with yanked versions' do
    stub_request(:get, "https://bcr.bazel.build/modules/rules_go/metadata.json")
      .to_return({ status: 200, body: file_fixture('bazel/rules_go_package_metadata') })
    stub_request(:get, "https://bcr.bazel.build/modules/rules_go/0.37.0/source.json")
      .to_return({ status: 200, body: file_fixture('bazel/rules_go_package_version_metadata1') })
    stub_request(:get, "https://bcr.bazel.build/modules/rules_go/0.59.0/source.json")
      .to_return({ status: 200, body: file_fixture('bazel/rules_go_package_version_metadata2') })
    package_metadata = @ecosystem.package_metadata('rules_go')
    yanked_version_metadata = @ecosystem.versions_metadata(package_metadata).first

    assert_equal yanked_version_metadata,
      {
        number: "0.37.0",
        status: "yanked",
        integrity: "sha256-VtjFpckeGvc+ynGm+rLO2Vm2fIbRK6N/7tsKLf6kQaY=",
        metadata: {
          type: "archive",
          patch_strip: nil,
          patches: nil,
          strip_prefix: "",
          url: "https://github.com/bazelbuild/rules_go/releases/download/v0.37.0/rules_go-v0.37.0.zip",
          mirror_urls: nil,
          overlay: nil,
          archive_type: nil
        }
      }
  end

  test 'maintainers_metadata' do
    stub_request(:get, "https://bcr.bazel.build/modules/rules_go/metadata.json")
      .to_return({ status: 200, body: file_fixture('bazel/rules_go_package_metadata') })
    maintainers_metadata = @ecosystem.maintainers_metadata('rules_go')
    assert_equal maintainers_metadata, [
      {
        uuid: 4312191,
        name: "Fabian Meumertzheim",
        login: "fmeum",
        email: "fabian@meumertzhe.im",
        do_not_notify: nil
      },
      {
        uuid: 98395,
        name: "Zhongpeng Lin",
        login: "linzhp",
        email: "zplin@uber.com",
        do_not_notify: nil
      },
      {
        uuid: 66684063,
        name: "Tyler French",
        login: "tyler-french",
        email: "tfrench@uber.com",
        do_not_notify: nil
      }
    ]
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:bazel/rules_go'
    assert Purl.parse(purl)
  end
end
