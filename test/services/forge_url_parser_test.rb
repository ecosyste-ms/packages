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
      'https://gitea.com/project',
    ].each do |url|
      assert_nil ForgeUrlParser.parse(url)
    end
  end
end
