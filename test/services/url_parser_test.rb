require "test_helper"

class UrlParserTest < ActiveSupport::TestCase
  test 'parses gitlab urls' do
    [
      ['https://gitlab.com/maxcdn/shml/', 'https://gitlab.com/maxcdn/shml'],
      ['https://gitlab.com/group/subgroup/project.git', 'https://gitlab.com/group/subgroup/project'],
      ['git+https://gitlab.com/hugojosefson/express-cluster-stability.git', 'https://gitlab.com/hugojosefson/express-cluster-stability'],
      ['www.gitlab.com/37point2/brainfuckifyjs', 'https://gitlab.com/37point2/brainfuckifyjs'],
      ['ssh+git@gitlab.com:omardelarosa/tonka-npm.git', 'https://gitlab.com/omardelarosa/tonka-npm'],
    ].each do |row|
      url, full_name = row
      result = UrlParser.try_all(url)
      assert_equal result, full_name
    end
  end

  test 'parses github urls' do
    [
      ['https://github.com/maxcdn/shml/', 'https://github.com/maxcdn/shml'],
      ['https://foo.github.io/bar', 'https://github.com/foo/bar'],
      ['git+https://github.com/hugojosefson/express-cluster-stability.git', 'https://github.com/hugojosefson/express-cluster-stability'],
      ['sughodke.github.com/linky.js/', 'https://github.com/sughodke/linky.js']
    ].each do |row|
      url, full_name = row
      result = UrlParser.try_all(url)
      assert_equal result, full_name
    end
  end

  test 'parses bitbucket urls' do
    [
      ['https://bitbucket.com/maxcdn/shml/', 'https://bitbucket.org/maxcdn/shml'],
      ['https://foo.bitbucket.org/bar', 'https://bitbucket.org/foo/bar'],
      ['git+https://bitbucket.com/hugojosefson/express-cluster-stability.git', 'https://bitbucket.org/hugojosefson/express-cluster-stability']
    ].each do |row|
      url, full_name = row
      result = UrlParser.try_all(url)
      assert_equal result, full_name
    end
  end

  test 'parses known forge host urls' do
    [
      ['https://codeberg.org/dnkl/foot/', 'https://codeberg.org/dnkl/foot'],
      ['git+https://codeberg.org/forgejo/forgejo.git', 'https://codeberg.org/forgejo/forgejo'],
      ['https://gitea.com/gitea/tea', 'https://gitea.com/gitea/tea'],
    ].each do |url, full_name|
      result = UrlParser.try_all(url)
      assert_equal result, full_name
    end
  end

  test 'parses configured self-hosted forge urls' do
    with_forge_hosts('https://gitea.example.com') do
      assert_equal 'https://gitea.example.com/org/repo', UrlParser.try_all('https://gitea.example.com/org/repo')
    end
  end

  private

  def with_forge_hosts(hosts)
    original_hosts = ENV['FORGE_HOSTS']
    ENV['FORGE_HOSTS'] = hosts
    yield
  ensure
    original_hosts.nil? ? ENV.delete('FORGE_HOSTS') : ENV['FORGE_HOSTS'] = original_hosts
  end
end
