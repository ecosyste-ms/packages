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

  test 'groups freebsd registries into one ecosystem card' do
    Registry.delete_all

    Registry.create!(
      name: 'freebsd-14-amd64',
      url: 'https://pkg.freebsd.org/FreeBSD:14:amd64/latest',
      ecosystem: 'freebsd',
      github: 'freebsd',
      version: '14',
      packages_count: 100
    )
    Registry.create!(
      name: 'freebsd-15-amd64',
      url: 'https://pkg.freebsd.org/FreeBSD:15:amd64/latest',
      ecosystem: 'freebsd',
      github: 'freebsd',
      version: '15',
      packages_count: 90
    )

    get root_path
    assert_response :success

    assert_match /href="\/ecosystems\/freebsd"/, response.body
    assert_select "div.registry", count: 1
  end
end