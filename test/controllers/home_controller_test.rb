require 'test_helper'

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
  end

  test 'renders index' do
    get root_path
    assert_response :success
    assert_template 'home/index'
  end

  test 'links to ecosystem using ecosystem field not github field' do
    # Clear existing registries to avoid interference
    Registry.delete_all

    # Create two alpine registries with different github and ecosystem values
    r1 = Registry.create!(
      name: 'alpine-v3.21',
      url: 'https://pkgs.alpinelinux.org/packages?branch=v3.21',
      ecosystem: 'alpine',
      github: 'alpinelinux',
      version: 'v3.21',
      packages_count: 100,
      default: false
    )
    r2 = Registry.create!(
      name: 'alpine-v3.20',
      url: 'https://pkgs.alpinelinux.org/packages?branch=v3.20',
      ecosystem: 'alpine',
      github: 'alpinelinux',
      version: 'v3.20',
      packages_count: 90,
      default: false
    )

    get root_path
    assert_response :success

    # Verify that the link uses the ecosystem field (alpine) not the github field (alpinelinux)
    assert_match /href="\/ecosystems\/alpine"/, response.body, "Should link to /ecosystems/alpine"
    refute_match /href="\/ecosystems\/alpinelinux"/, response.body, "Should not link to /ecosystems/alpinelinux"
  end
end