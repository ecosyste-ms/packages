# frozen_string_literal: true

require 'test_helper'

class EasyconfigParserTest < ActiveSupport::TestCase
  test 'parses basic metadata, toolchain, and dependencies' do
    eb = <<~EB
      easyblock = 'PythonBundle'
      name = 'TensorFlow'
      version = '2.13.0'
      versionsuffix = '-CUDA-12.1.1'
      homepage = 'https://www.tensorflow.org/'
      description = """An open-source software library for Machine Intelligence"""
      toolchain = {'name': 'foss', 'version': '2023a'}

      source_urls = ['https://github.com/tensorflow/tensorflow/archive']
      sources = ['v%(version)s.tar.gz']
      patches = ['TensorFlow-fix.patch']
      checksums = ['abcdef1234567890']

      builddependencies = [
          ('Bazel', '6.3.1'),
          ('git', '2.41.0', '-nodocs')
      ]
      dependencies = [
          ('Python', '3.11.3'),
          ('h5py', '3.9.0'),
          ('OpenSSL', '1.1', '', SYSTEM)
      ]
    EB

    parsed = EasyconfigParser.parse(eb)

    assert_equal 'TensorFlow', parsed[:name]
    assert_equal '2.13.0', parsed[:version]
    assert_equal '-CUDA-12.1.1', parsed[:versionsuffix]
    assert_equal 'https://www.tensorflow.org/', parsed[:homepage]
    assert_equal 'An open-source software library for Machine Intelligence', parsed[:description]
    assert_equal 'PythonBundle', parsed[:easyblock]

    assert_equal({ name: 'foss', version: '2023a' }, parsed[:toolchain])

    assert_equal ['https://github.com/tensorflow/tensorflow/archive'], parsed[:source_urls]
    assert_equal ['v%(version)s.tar.gz'], parsed[:sources]
    assert_equal ['TensorFlow-fix.patch'], parsed[:patches]
    assert_equal ['abcdef1234567890'], parsed[:checksums]

    assert_equal 2, parsed[:builddependencies].length
    assert_equal 'Bazel', parsed[:builddependencies][0][:name]
    assert_equal '6.3.1', parsed[:builddependencies][0][:version]
    assert_equal 'build', parsed[:builddependencies][0][:kind]

    assert_equal 3, parsed[:dependencies].length
    assert_equal 'Python', parsed[:dependencies][0][:name]
    assert_equal '3.11.3', parsed[:dependencies][0][:version]
    assert_equal 'runtime', parsed[:dependencies][0][:kind]
    assert_equal 'OpenSSL', parsed[:dependencies][2][:name]
    assert_equal '1.1', parsed[:dependencies][2][:version]
  end

  test 'handles SYSTEM toolchain and triple single-quoted description' do
    eb = <<~EB
      name = 'zlib'
      version = '1.2.13'
      homepage = 'https://www.zlib.net/'
      description = '''A massively spiffy yet delicately unobtrusive compression library'''
      toolchain = SYSTEM
      dependencies = []
    EB

    parsed = EasyconfigParser.parse(eb)

    assert_equal 'zlib', parsed[:name]
    assert_equal '1.2.13', parsed[:version]
    assert_equal 'https://www.zlib.net/', parsed[:homepage]
    assert_equal 'A massively spiffy yet delicately unobtrusive compression library', parsed[:description]
    assert_equal({ name: 'system' }, parsed[:toolchain])
    assert_empty parsed[:dependencies]
  end

  test 'returns empty attributes gracefully on empty or malformed input' do
    parsed = EasyconfigParser.parse('')

    assert_nil parsed[:name]
    assert_nil parsed[:version]
    assert_nil parsed[:homepage]
    assert_nil parsed[:description]
    assert_empty parsed[:toolchain]
    assert_empty parsed[:dependencies]
    assert_empty parsed[:builddependencies]
  end
end
