require "test_helper"

class WingetTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: "winget-pkgs", url: "https://github.com/microsoft/winget-pkgs", ecosystem: "winget", default: true)
    @ecosystem = Ecosystem::Winget.new(@registry)
    @package = Package.new(ecosystem: "winget", name: "Microsoft.VisualStudioCode")
    @version = @package.versions.build(number: "1.90.0", metadata: { "path" => "manifests/m/Microsoft/VisualStudioCode/1.90.0" })
  end

  test "registry_url" do
    assert_equal "https://github.com/microsoft/winget-pkgs/tree/master/manifests/m/Microsoft/VisualStudioCode", @ecosystem.registry_url(@package)
  end

  test "registry_url with version" do
    assert_equal "https://github.com/microsoft/winget-pkgs/tree/master/manifests/m/Microsoft/VisualStudioCode/1.90.0", @ecosystem.registry_url(@package, @version)
  end

  test "install_command" do
    assert_equal "winget install --id Microsoft.VisualStudioCode", @ecosystem.install_command(@package)
    assert_equal "winget install --id Microsoft.VisualStudioCode --version 1.90.0", @ecosystem.install_command(@package, "1.90.0")
  end

  test "all_package_names" do
    stub_tree

    assert_equal ["Microsoft.VisualStudioCode"], @ecosystem.all_package_names
  end

  test "package_metadata" do
    stub_tree
    stub_manifests

    metadata = @ecosystem.package_metadata("Microsoft.VisualStudioCode")

    assert_equal "Microsoft.VisualStudioCode", metadata[:name]
    assert_equal "Code editing. Redefined.", metadata[:description]
    assert_equal "https://code.visualstudio.com/", metadata[:homepage]
    assert_equal ["MIT"], metadata[:licenses]
    assert_equal "Microsoft Corporation", metadata[:metadata][:publisher]
  end

  test "versions_metadata" do
    stub_tree
    stub_manifests

    versions = @ecosystem.versions_metadata({ name: "Microsoft.VisualStudioCode", versions: ["manifests/m/Microsoft/VisualStudioCode/1.90.0"] })

    assert_equal 1, versions.length
    assert_equal "1.90.0", versions.first[:number]
    assert_equal "manifests/m/Microsoft/VisualStudioCode/1.90.0", versions.first[:metadata][:path]
    assert_equal "1.6.0", versions.first[:metadata][:manifest_version]
  end

  private

  def stub_tree
    @ecosystem.stubs(:get_json).returns(
      "tree" => [
        { "path" => "manifests/m/Microsoft/VisualStudioCode/1.90.0/Microsoft.VisualStudioCode.yaml" },
        { "path" => "manifests/m/Microsoft/VisualStudioCode/1.90.0/Microsoft.VisualStudioCode.locale.en-US.yaml" },
        { "path" => "manifests/m/Microsoft/VisualStudioCode/1.90.0/Microsoft.VisualStudioCode.installer.yaml" },
        { "path" => "README.md" }
      ]
    )
  end

  def stub_manifests
    base = "https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/m/Microsoft/VisualStudioCode/1.90.0"
    stub_request(:get, "#{base}/Microsoft.VisualStudioCode.yaml")
      .to_return(status: 200, body: <<~YAML)
        PackageIdentifier: Microsoft.VisualStudioCode
        PackageVersion: 1.90.0
        DefaultLocale: en-US
        ManifestVersion: 1.6.0
      YAML
    stub_request(:get, "#{base}/Microsoft.VisualStudioCode.locale.en-US.yaml")
      .to_return(status: 200, body: <<~YAML)
        PackageIdentifier: Microsoft.VisualStudioCode
        PackageVersion: 1.90.0
        PackageLocale: en-US
        Publisher: Microsoft Corporation
        PackageName: Microsoft Visual Studio Code
        License: MIT
        ShortDescription: Code editing. Redefined.
        PackageUrl: https://code.visualstudio.com/
        Tags:
          - editor
          - vscode
        ManifestVersion: 1.6.0
      YAML
    stub_request(:get, "#{base}/Microsoft.VisualStudioCode.installer.yaml")
      .to_return(status: 200, body: <<~YAML)
        PackageIdentifier: Microsoft.VisualStudioCode
        PackageVersion: 1.90.0
        InstallerType: exe
        Scope: user
        ManifestVersion: 1.6.0
      YAML
  end
end
