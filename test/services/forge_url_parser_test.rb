require "test_helper"

class ForgeUrlParserTest < ActiveSupport::TestCase
  test 'parses known forge host urls' do
    [
      ['https://codeberg.org/dnkl/foot/', 'dnkl/foot'],
      ['git+https://codeberg.org/forgejo/forgejo.git', 'forgejo/forgejo'],
      ['ssh://git@codeberg.org:forgejo/forgejo.git', 'forgejo/forgejo'],
      ['https://codeberg.org/forgejo/forgejo/src/branch/main', 'forgejo/forgejo'],
      ['https://gitea.com/gitea/tea', 'gitea/tea'],
      ['git@gitea.com:gitea/tea.git', 'gitea/tea'],
    ].each do |url, full_name|
      assert_equal full_name, ForgeUrlParser.parse(url)
    end
  end

  test 'does not parse unknown forge-like hosts' do
    [
      'https://forgejo.example.com/group/project',
      'https://codeberg.org/project',
      'https://notcodeberg.org/group/project',
      'https://example.com/codeberg.org/group/project',
      'https://gitea.com/project',
    ].each do |url|
      assert_nil ForgeUrlParser.parse(url)
    end
  end

  test 'parses configured self-hosted forge urls' do
    with_forge_hosts('https://gitea.example.com,https://forgejo.example.com/forgejo') do
      assert_equal 'org/repo', ForgeUrlParser.parse('https://gitea.example.com/org/repo')
      assert_equal 'group/project', ForgeUrlParser.parse('https://forgejo.example.com/forgejo/group/project')
      assert_equal 'https://forgejo.example.com/forgejo/group/project', ForgeUrlParser.parse_to_full_url('https://forgejo.example.com/forgejo/group/project')
      assert_nil ForgeUrlParser.parse('https://forgejo.example.com/group/project')
    end
  end

  test 'ignores invalid configured forge hosts' do
    with_forge_hosts('gitea.example.com,https://forgejo.example.com?source=configuration') do
      assert_nil ForgeUrlParser.parse('https://gitea.example.com/org/repo')
      assert_nil ForgeUrlParser.parse('https://forgejo.example.com/group/project')
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
