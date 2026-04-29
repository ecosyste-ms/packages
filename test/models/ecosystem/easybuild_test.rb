require "test_helper"

class EasybuildTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: "docs.easybuild.io", url: "https://docs.easybuild.io", ecosystem: "easybuild", default: true)
    @ecosystem = Ecosystem::Easybuild.new(@registry)
    @package = Package.new(ecosystem: "easybuild", name: "zlib")
    @version = @package.versions.build(number: "1.3.1", metadata: { "path" => "easybuild/easyconfigs/z/zlib/zlib-1.3.1-GCCcore-13.2.0.eb" })
  end

  test "registry_url" do
    assert_equal "https://docs.easybuild.io/version-specific/supported-software/zlib/", @ecosystem.registry_url(@package)
  end

  test "registry_url with version" do
    assert_equal "https://github.com/easybuilders/easybuild-easyconfigs/blob/develop/easybuild/easyconfigs/z/zlib/zlib-1.3.1-GCCcore-13.2.0.eb", @ecosystem.registry_url(@package, @version)
  end

  test "install_command" do
    assert_equal "eb zlib", @ecosystem.install_command(@package)
    assert_equal "eb zlib-1.3.1.eb", @ecosystem.install_command(@package, "1.3.1")
  end

  test "all_package_names" do
    @ecosystem.stubs(:get_json).returns(
      "tree" => [
        { "path" => "easybuild/easyconfigs/z/zlib/zlib-1.3.1-GCCcore-13.2.0.eb" },
        { "path" => "easybuild/easyconfigs/r/Redis/Redis-7.2.4-GCCcore-13.2.0.eb" },
        { "path" => "README.md" }
      ]
    )

    assert_equal ["Redis", "zlib"], @ecosystem.all_package_names
  end

  test "package_metadata" do
    stub_tree
    stub_easyconfig("zlib-1.3.1-GCCcore-13.2.0.eb", easyconfig_content)

    metadata = @ecosystem.package_metadata("zlib")

    assert_equal "zlib", metadata[:name]
    assert_equal "A free, general-purpose data compression library.", metadata[:description]
    assert_equal "https://zlib.net/", metadata[:homepage]
    assert_equal "Zlib", metadata[:metadata][:easyblock]
    assert_equal({ "name" => "GCCcore", "version" => "13.2.0" }, metadata[:metadata][:toolchain])
  end

  test "versions_metadata" do
    stub_easyconfig("zlib-1.3.1-GCCcore-13.2.0.eb", easyconfig_content)

    versions = @ecosystem.versions_metadata({ name: "zlib", versions: ["easybuild/easyconfigs/z/zlib/zlib-1.3.1-GCCcore-13.2.0.eb"] })

    assert_equal 1, versions.length
    assert_equal "1.3.1", versions.first[:number]
    assert_equal "easybuild/easyconfigs/z/zlib/zlib-1.3.1-GCCcore-13.2.0.eb", versions.first[:metadata][:path]
    assert_equal({ "name" => "GCCcore", "version" => "13.2.0" }, versions.first[:metadata][:toolchain])
  end

  test "dependencies_metadata" do
    stub_easyconfig("zlib-1.3.1-GCCcore-13.2.0.eb", easyconfig_content)

    dependencies = @ecosystem.dependencies_metadata("zlib", @version, @package)

    assert_equal ["binutils"], dependencies.map { |dependency| dependency[:package_name] }
    assert_equal "runtime", dependencies.first[:kind]
    assert_equal "easybuild", dependencies.first[:ecosystem]
  end

  private

  def stub_tree
    @ecosystem.stubs(:get_json).returns(
      "tree" => [
        { "path" => "easybuild/easyconfigs/z/zlib/zlib-1.2.13-GCCcore-12.3.0.eb" },
        { "path" => "easybuild/easyconfigs/z/zlib/zlib-1.3.1-GCCcore-13.2.0.eb" }
      ]
    )
  end

  def stub_easyconfig(file, body)
    stub_request(:get, "https://raw.githubusercontent.com/easybuilders/easybuild-easyconfigs/develop/easybuild/easyconfigs/z/zlib/#{file}")
      .to_return(status: 200, body: body)
  end

  def easyconfig_content
    <<~EASYCONFIG
      easyblock = 'Zlib'
      name = 'zlib'
      version = '1.3.1'
      homepage = 'https://zlib.net/'
      description = """A free, general-purpose data compression library."""
      toolchain = {'name': 'GCCcore', 'version': '13.2.0'}
      source_urls = ['https://zlib.net/fossils/']
      sources = ['%(name)s-%(version)s.tar.gz']
      dependencies = [
          ('binutils', '2.40'),
      ]
    EASYCONFIG
  end
end
