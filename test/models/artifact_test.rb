require "test_helper"

class ArtifactTest < ActiveSupport::TestCase
  subject { @version.artifacts.build(identifier: 'module') }

  context 'associations' do
    should belong_to(:version)
  end

  context 'validations' do
    should validate_presence_of(:version_id)
    should validate_presence_of(:identifier)
    should validate_uniqueness_of(:identifier).scoped_to(:version_id)
  end

  setup do
    registry = Registry.create!(name: 'proxy.golang.org', url: 'https://proxy.golang.org', ecosystem: 'go')
    package = registry.packages.create!(name: 'example.com/module', ecosystem: 'go')
    @version = package.versions.create!(number: 'v1.0.0', registry: registry)
  end

  test 'accepts an opaque integrity value' do
    artifact = @version.artifacts.create!(identifier: 'module.zip', integrity: 'h1:AbCdEf==')

    assert_equal 'h1:AbCdEf==', artifact.integrity
  end

  test 'indexes integrity with a partial hash index' do
    index = ActiveRecord::Base.connection.indexes(:artifacts).find do |candidate|
      candidate.name == 'index_artifacts_on_integrity'
    end

    assert_equal :hash, index.using
    assert_equal '(integrity IS NOT NULL)', index.where
  end
end
