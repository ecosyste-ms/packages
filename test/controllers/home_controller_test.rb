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
end