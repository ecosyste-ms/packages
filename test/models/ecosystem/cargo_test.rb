require "test_helper"

class CargoTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'Crates.io', url: 'https://crates.io', ecosystem: 'Cargo')
    @ecosystem = Ecosystem::Cargo.new(@registry)
    @package = Package.new(ecosystem: 'Cargo', name: 'rand')
    @version = @package.versions.build(number: '0.8.5')
    @maintainer = @registry.maintainers.build(login: 'foo')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://crates.io/crates/rand/'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://crates.io/crates/rand/0.8.5'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://static.crates.io/crates/rand/rand-0.8.5.crate'
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, "https://docs.rs/rand/"
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_equal documentation_url, "https://docs.rs/rand/0.8.5"
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'cargo install rand'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'cargo install rand --version 0.8.5'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://crates.io/api/v1/crates/rand"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:cargo/rand'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:cargo/rand@0.8.5'
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://crates.io/api/v1/crates?page=1&per_page=100")
      .to_return({ status: 200, body: file_fixture('cargo/crates') })
    stub_request(:get, "https://crates.io/api/v1/crates?page=2&per_page=100")
      .to_return({ status: 200, body: file_fixture('cargo/crates2') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 100
    assert_equal all_package_names.last, 'aba-cache'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://crates.io/api/v1/summary")
      .to_return({ status: 200, body: file_fixture('cargo/summary') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 20
    assert_equal recently_updated_package_names.last, 'findsrouce'
  end

  test 'package_metadata' do
    stub_request(:get, "https://crates.io/api/v1/crates/parameters_lib")
      .to_return({ status: 200, body: file_fixture('cargo/parameters_lib') })
    package_metadata = @ecosystem.package_metadata('parameters_lib')
    
    assert_equal package_metadata[:name], "parameters_lib"
    assert_equal package_metadata[:description], "Parameters Library"
    assert_equal package_metadata[:homepage], "https://github.com/TheFox/parameters-rust"
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal package_metadata[:repository_url], "https://github.com/TheFox/parameters-rust"
    assert_equal package_metadata[:keywords_array], ["env", "variables"]
    assert_equal package_metadata[:downloads], 797
    assert_equal package_metadata[:downloads_period], 'total'
    assert_equal package_metadata[:metadata], {:categories=>["parsing", "filesystem", "config", "command-line-interface"]}
  end

  test 'versions_metadata' do
    stub_request(:get, "https://crates.io/api/v1/crates/parameters_lib")
      .to_return({ status: 200, body: file_fixture('cargo/parameters_lib') })
    package_metadata = @ecosystem.package_metadata('parameters_lib')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [{:number=>"0.2.2",
    :published_at=>"2022-03-29T13:35:06.927472+00:00",
    :status=>nil,
    :metadata=>
     {:uuid=>523961,
      :downloads=>473,
      :published_by=>
       {"avatar"=>"https://avatars.githubusercontent.com/u/353709?v=4",
        "id"=>65133,
        "login"=>"TheFox",
        "name"=>"Christian Mayer",
        "url"=>"https://github.com/TheFox"},
      :checksum=>"bced3bcb3f52104ec2c5d32d23b0b76fb4079a3567025f64ef500082bc29f2c3",
      :size=>nil,
      :license=>"MIT",
      :crate_size=>3200,
      :rust_version=>nil,
      :features=>{},
      :yanked=>false,
      :yank_message=>nil,
      :dl_path=>"/api/v1/crates/parameters_lib/0.2.2/download",
      :audit_actions=>[{"action"=>"publish", "time"=>"2022-03-29T13:35:06.927472+00:00", "user"=>{"avatar"=>"https://avatars.githubusercontent.com/u/353709?v=4", "id"=>65133, "login"=>"TheFox", "name"=>"Christian Mayer", "url"=>"https://github.com/TheFox"}}],
      :lib_links=>nil,
      :has_lib=>nil,
      :bin_names=>nil,
      :edition=>nil}},
   {:number=>"0.1.0",
    :published_at=>"2022-03-24T16:19:57.595451+00:00",
    :status=>nil,
    :metadata=>
     {:uuid=>521540,
      :downloads=>120,
      :published_by=>
       {"avatar"=>"https://avatars.githubusercontent.com/u/353709?v=4",
        "id"=>65133,
        "login"=>"TheFox",
        "name"=>"Christian Mayer",
        "url"=>"https://github.com/TheFox"},
      :checksum=>"3c73ba40f4d2fc31375a39ce83d08695993f14c411f6907fe032535843811806",
      :size=>nil,
      :license=>"MIT",
      :crate_size=>3033,
      :rust_version=>nil,
      :features=>{},
      :yanked=>false,
      :yank_message=>nil,
      :dl_path=>"/api/v1/crates/parameters_lib/0.1.0/download",
      :audit_actions=>[{"action"=>"publish", "time"=>"2022-03-24T16:19:57.595451+00:00", "user"=>{"avatar"=>"https://avatars.githubusercontent.com/u/353709?v=4", "id"=>65133, "login"=>"TheFox", "name"=>"Christian Mayer", "url"=>"https://github.com/TheFox"}}],
      :lib_links=>nil,
      :has_lib=>nil,
      :bin_names=>nil,
      :edition=>nil}},
   {:number=>"0.1.0-dev.2",
    :published_at=>"2022-03-24T16:08:54.337646+00:00",
    :status=>nil,
    :metadata=>
     {:uuid=>521537,
      :downloads=>100,
      :published_by=>
       {"avatar"=>"https://avatars.githubusercontent.com/u/353709?v=4",
        "id"=>65133,
        "login"=>"TheFox",
        "name"=>"Christian Mayer",
        "url"=>"https://github.com/TheFox"},
      :checksum=>"5f9bef8f40cfbd69b1cb8e9de369940adb6fc676dddcb878afcd5683f883e5de",
      :size=>nil,
      :license=>"MIT",
      :crate_size=>3039,
      :rust_version=>nil,
      :features=>{},
      :yanked=>false,
      :yank_message=>nil,
      :dl_path=>"/api/v1/crates/parameters_lib/0.1.0-dev.2/download",
      :audit_actions=>[{"action"=>"publish", "time"=>"2022-03-24T16:08:54.337646+00:00", "user"=>{"avatar"=>"https://avatars.githubusercontent.com/u/353709?v=4", "id"=>65133, "login"=>"TheFox", "name"=>"Christian Mayer", "url"=>"https://github.com/TheFox"}}],
      :lib_links=>nil,
      :has_lib=>nil,
      :bin_names=>nil,
      :edition=>nil}},
   {:number=>"0.1.0-dev.1",
    :published_at=>"2022-03-24T15:58:36.858899+00:00",
    :status=>nil,
    :metadata=>
     {:uuid=>521532,
      :downloads=>102,
      :published_by=>
       {"avatar"=>"https://avatars.githubusercontent.com/u/353709?v=4",
        "id"=>65133,
        "login"=>"TheFox",
        "name"=>"Christian Mayer",
        "url"=>"https://github.com/TheFox"},
      :checksum=>"dcd44068a1f7ff7a8069aab2b41c6c5f378806bf22119e399ca04e4da1633ab6",
      :size=>nil,
      :license=>"MIT",
      :crate_size=>3026,
      :rust_version=>nil,
      :features=>{},
      :yanked=>false,
      :yank_message=>nil,
      :dl_path=>"/api/v1/crates/parameters_lib/0.1.0-dev.1/download",
      :audit_actions=>[{"action"=>"publish", "time"=>"2022-03-24T15:58:36.858899+00:00", "user"=>{"avatar"=>"https://avatars.githubusercontent.com/u/353709?v=4", "id"=>65133, "login"=>"TheFox", "name"=>"Christian Mayer", "url"=>"https://github.com/TheFox"}}],
      :lib_links=>nil,
      :has_lib=>nil,
      :bin_names=>nil,
      :edition=>nil}}]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://crates.io/api/v1/crates/parameters_lib/0.1.0/dependencies")
      .to_return({ status: 200, body: file_fixture('cargo/dependencies') })
    dependencies_metadata = @ecosystem.dependencies_metadata('parameters_lib', '0.1.0', nil)
    
    assert_equal dependencies_metadata, [{:package_name=>"regex", :requirements=>"^1.5.0", :kind=>"normal", :optional=>false, :ecosystem=>"cargo"}]
  end

  test 'maintainer_url' do 
    assert_equal @ecosystem.maintainer_url(@maintainer), 'https://crates.io/users/foo'
  end

  test 'versions_metadata includes cargo specific fields' do
    stub_request(:get, "https://crates.io/api/v1/crates/parameters_lib")
      .to_return({ status: 200, body: file_fixture('cargo/parameters_lib') })
    package_metadata = @ecosystem.package_metadata('parameters_lib')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)
    
    first_version = versions_metadata.first
    assert_equal first_version[:metadata][:features], {}
    assert_equal first_version[:metadata][:yanked], false
    assert_equal first_version[:metadata][:dl_path], "/api/v1/crates/parameters_lib/0.2.2/download"
    assert_equal first_version[:metadata][:audit_actions].first["action"], "publish"
    assert_nil first_version[:metadata][:rust_version]
  end

  test 'versions_metadata includes newer cargo api fields' do
    stub_request(:get, "https://crates.io/api/v1/crates/serde")
      .to_return({ status: 200, body: file_fixture('cargo/serde_fresh') })
    package_metadata = @ecosystem.package_metadata('serde')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)
    
    first_version = versions_metadata.first
    assert_equal first_version[:metadata][:edition], "2018"
    assert_equal first_version[:metadata][:rust_version], "1.31"
    assert_equal first_version[:metadata][:has_lib], true
    assert_equal first_version[:metadata][:bin_names], []
    assert_nil first_version[:metadata][:yank_message]
    assert_nil first_version[:metadata][:lib_links]
    assert_equal first_version[:metadata][:features]["default"], ["std"]
  end
end
