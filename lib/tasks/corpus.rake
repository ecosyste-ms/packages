require_relative '../package_corpus_export'
require_relative '../corpus_upload'

namespace :exports do
  desc 'Export selected packages and supplied project groups (ASSIGNMENTS=manifest.json OUTPUT=corpus.tar.gz; optional SOURCE=packages.ndjson.gz UPLOAD=true)'
  task corpus: :environment do
    upload = ENV.fetch('UPLOAD', 'false')
    raise ArgumentError, 'UPLOAD must be true or false' unless %w[true false].include?(upload)
    uploader = if upload == 'true'
      CorpusUpload.new(endpoint: ENV.fetch('S3_ENDPOINT'), bucket: ENV.fetch('S3_BUCKET'), region: ENV.fetch('S3_REGION', 'auto'),
        access_key: ENV.fetch('AWS_ACCESS_KEY_ID'), secret_key: ENV.fetch('AWS_SECRET_ACCESS_KEY'), session_token: ENV['AWS_SESSION_TOKEN'])
    end
    result = PackageCorpusExport.new(manifest: ENV.fetch('ASSIGNMENTS'), output: ENV.fetch('OUTPUT'),
      source: ENV['SOURCE'], batch_size: ENV.fetch('BATCH_SIZE', '250')).run
    puts JSON.generate(result.slice('records', 'projects', 'excluded_packages', 'source', 'archive', 'archive_sha256'))
    if uploader
      key = [ENV.fetch('S3_PREFIX', 'package-corpus').sub(%r{/+\z}, ''), result.fetch('archive_sha256') + '.tar.gz'].reject(&:empty?).join('/')
      puts JSON.generate(upload: uploader.upload(result.fetch('archive'), key: key))
    end
  end

  desc 'Upload an existing corpus archive (FILE=corpus.tar.gz S3_ENDPOINT=... S3_BUCKET=...)'
  task :upload_corpus do
    path = ENV.fetch('FILE')
    uploader = CorpusUpload.new(endpoint: ENV.fetch('S3_ENDPOINT'), bucket: ENV.fetch('S3_BUCKET'), region: ENV.fetch('S3_REGION', 'auto'),
      access_key: ENV.fetch('AWS_ACCESS_KEY_ID'), secret_key: ENV.fetch('AWS_SECRET_ACCESS_KEY'), session_token: ENV['AWS_SESSION_TOKEN'])
    key = [ENV.fetch('S3_PREFIX', 'package-corpus').sub(%r{/+\z}, ''), Digest::SHA256.file(path).hexdigest + '.tar.gz'].reject(&:empty?).join('/')
    puts JSON.generate(upload: uploader.upload(path, key: key))
  end
end
