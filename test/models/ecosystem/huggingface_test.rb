require "test_helper"

class HuggingfaceTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'huggingface.co', url: 'https://huggingface.co', ecosystem: 'huggingface')
    @ecosystem = Ecosystem::Huggingface.new(@registry)
    @package = Package.new(ecosystem: @registry.ecosystem, name: 'google-bert/bert-base-uncased')
    @version = @package.versions.build(number: '86b5e0934494bd15c9632b12f734a8a67f723594')
  end

  test 'registry_url' do
    assert_equal 'https://huggingface.co/google-bert/bert-base-uncased', @ecosystem.registry_url(@package)
  end

  test 'registry_url with version' do
    assert_equal 'https://huggingface.co/google-bert/bert-base-uncased/tree/86b5e0934494bd15c9632b12f734a8a67f723594', @ecosystem.registry_url(@package, @version.number)
  end

  test 'download_url' do
    assert_equal 'https://huggingface.co/google-bert/bert-base-uncased/resolve/main/config.json', @ecosystem.download_url(@package)
    assert_equal 'https://huggingface.co/google-bert/bert-base-uncased/resolve/86b5e0934494bd15c9632b12f734a8a67f723594/config.json', @ecosystem.download_url(@package, @version.number)
  end

  test 'documentation_url' do
    assert_equal 'https://huggingface.co/google-bert/bert-base-uncased', @ecosystem.documentation_url(@package)
  end

  test 'install_command' do
    assert_equal 'huggingface-cli download google-bert/bert-base-uncased', @ecosystem.install_command(@package)
  end

  test 'install_command with version' do
    assert_equal 'huggingface-cli download google-bert/bert-base-uncased --revision 86b5e0934494bd15c9632b12f734a8a67f723594', @ecosystem.install_command(@package, @version.number)
  end

  test 'purl' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal 'pkg:huggingface/google-bert/bert-base-uncased@86b5e0934494bd15c9632b12f734a8a67f723594', purl
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, 'https://huggingface.co/api/models?limit=100')
      .to_return({ status: 200, body: huggingface_list_response })

    assert_equal ['google-bert/bert-base-uncased', 'openai/privacy-filter'], @ecosystem.all_package_names
  end

  test 'recently_updated_package_names' do
    stub_request(:get, 'https://huggingface.co/api/models?direction=-1&limit=100&sort=lastModified')
      .to_return({ status: 200, body: huggingface_list_response })

    assert_equal ['google-bert/bert-base-uncased', 'openai/privacy-filter'], @ecosystem.recently_updated_package_names
  end

  test 'package_metadata' do
    stub_huggingface_model_lookup

    metadata = @ecosystem.package_metadata('google-bert/bert-base-uncased')

    assert_equal 'google-bert/bert-base-uncased', metadata[:name]
    assert_equal 'fill-mask', metadata[:description]
    assert_equal 'https://huggingface.co/google-bert/bert-base-uncased', metadata[:homepage]
    assert_equal 'https://huggingface.co/google-bert/bert-base-uncased', metadata[:repository_url]
    assert_equal ['transformers', 'license:apache-2.0', 'fill-mask'], metadata[:keywords_array]
    assert_equal 'apache-2.0', metadata[:licenses]
    assert_equal 58_054_642, metadata[:downloads]
    assert_equal 'total', metadata[:downloads_period]
    assert_equal ['86b5e0934494bd15c9632b12f734a8a67f723594'], metadata[:versions]
    assert_equal ['config.json', 'model.safetensors'], metadata[:metadata]['siblings']
  end

  test 'versions_metadata' do
    stub_huggingface_model_lookup

    metadata = @ecosystem.package_metadata('google-bert/bert-base-uncased')
    versions = @ecosystem.versions_metadata(metadata)

    assert_equal 1, versions.length
    assert_equal '86b5e0934494bd15c9632b12f734a8a67f723594', versions.first[:number]
    assert_equal 'apache-2.0', versions.first[:licenses]
    assert_equal '2024-02-19T11:06:12.000Z', versions.first[:published_at]
  end

  private

  def stub_huggingface_model_lookup
    stub_request(:get, 'https://huggingface.co/api/models/google-bert/bert-base-uncased')
      .to_return({ status: 200, body: huggingface_model_response })
  end

  def huggingface_list_response
    [
      { id: 'google-bert/bert-base-uncased' },
      { id: 'openai/privacy-filter' }
    ].to_json
  end

  def huggingface_model_response
    {
      id: 'google-bert/bert-base-uncased',
      modelId: 'google-bert/bert-base-uncased',
      author: 'google-bert',
      sha: '86b5e0934494bd15c9632b12f734a8a67f723594',
      pipeline_tag: 'fill-mask',
      library_name: 'transformers',
      tags: ['transformers', 'license:apache-2.0', 'fill-mask'],
      downloads: 58_054_642,
      lastModified: '2024-02-19T11:06:12.000Z',
      siblings: [
        { rfilename: 'config.json' },
        { rfilename: 'model.safetensors' }
      ]
    }.to_json
  end
end
