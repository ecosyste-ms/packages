require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  def load_seeds
    silence_warnings { load Rails.root.join('db/seeds.rb') }
  end

  test 'seeds every current ubuntu release' do
    load_seeds

    releases = Registry.where(ecosystem: 'ubuntu').to_h { |registry| [registry.version, registry.metadata['codename']] }
    assert_equal({ '26.10' => 'stonking', '26.04' => 'resolute', '25.10' => 'questing', '25.04' => 'plucky' }, releases.slice('26.10', '26.04', '25.10', '25.04'))

    registry = Registry.find_by!(name: 'ubuntu-26.04')
    assert_equal 'https://launchpad.net/ubuntu/resolute', registry.url
    assert_nil registry.metadata['mirror']
    assert_equal 'http://archive.ubuntu.com/ubuntu', registry.ecosystem_instance.mirror_url
  end

  test 'seeding again keeps one registry per ubuntu release and one default' do
    2.times { load_seeds }

    ubuntu = Registry.where(ecosystem: 'ubuntu')
    assert_equal ubuntu.distinct.count(:version), ubuntu.count
    assert_equal ['ubuntu-24.04'], ubuntu.where(default: true).pluck(:name)
  end
end
