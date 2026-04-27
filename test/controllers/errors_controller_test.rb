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
end
