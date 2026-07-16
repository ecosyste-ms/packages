require 'test_helper'

class ErrorsControllerTest < ActionDispatch::IntegrationTest
  test 'renders 404' do
    get '/404'
    assert_response :not_found
    assert_template 'errors/not_found'
  end

  test 'renders 422' do
    get '/422'
    assert_response :unprocessable_content
    assert_template 'errors/unprocessable'
  end

  test 'renders 500' do
    get '/500'
    assert_response :internal_server_error
    assert_template 'errors/internal'
  end

  test '500 is not publicly cacheable' do
    get '/500'
    cache_control = response.headers['Cache-Control'].to_s
    refute_includes cache_control, 'public', "got: #{cache_control}"
    refute_includes cache_control, 's-maxage', "got: #{cache_control}"
  end

  test '404 is not publicly cacheable' do
    get '/404'
    cache_control = response.headers['Cache-Control'].to_s
    refute_includes cache_control, 'public', "got: #{cache_control}"
    refute_includes cache_control, 's-maxage', "got: #{cache_control}"
  end

  test '422 is not publicly cacheable' do
    get '/422'
    cache_control = response.headers['Cache-Control'].to_s
    refute_includes cache_control, 'public', "got: #{cache_control}"
    refute_includes cache_control, 's-maxage', "got: #{cache_control}"
  end

  test 'json 500 is not publicly cacheable' do
    get '/500', as: :json
    cache_control = response.headers['Cache-Control'].to_s
    refute_includes cache_control, 'public', "got: #{cache_control}"
    refute_includes cache_control, 's-maxage', "got: #{cache_control}"
  end

  test 'path traversal renders 404 through exceptions_app' do
    # With show_exceptions enabled, RecordNotFound is re-dispatched through
    # the router to ErrorsController. The router merges (not replaces) path
    # params, so the original traversal id is still present when
    # ErrorsController runs; it must skip reject_path_traversal_in_params
    # or the failsafe 500 is returned instead.
    Registry.create(name: 'npmjs.org', url: 'https://npmjs.org', ecosystem: 'npm')
    with_show_exceptions(:all) do
      get '/registries/npmjs.org/namespaces/..%2F..%2F..'
      assert_response :not_found
      assert_template 'errors/not_found'
    end
  end

  def with_show_exceptions(value)
    env_config = Rails.application.env_config
    old_show = env_config['action_dispatch.show_exceptions']
    old_detailed = env_config['action_dispatch.show_detailed_exceptions']
    env_config['action_dispatch.show_exceptions'] = value
    env_config['action_dispatch.show_detailed_exceptions'] = false
    yield
  ensure
    env_config['action_dispatch.show_exceptions'] = old_show
    env_config['action_dispatch.show_detailed_exceptions'] = old_detailed
  end
end
