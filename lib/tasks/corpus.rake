require_relative '../package_corpus_export'
require_relative '../corpus_upload'

namespace :exports do
  desc 'Select, group and export packages from the database (optional TARGET=300000 OUTPUT=corpus.tar.gz UPLOAD=true)'
  task corpus: :environment do
    upload = ENV.fetch('UPLOAD', 'false')
    raise ArgumentError, 'UPLOAD must be true or false' unless %w[true false].include?(upload)
    uploader = if upload == 'true'
      CorpusUpload.new(endpoint: ENV.fetch('S3_ENDPOINT'), bucket: ENV.fetch('S3_BUCKET'), region: ENV.fetch('S3_REGION', 'auto'),
        access_key: ENV.fetch('AWS_ACCESS_KEY_ID'), secret_key: ENV.fetch('AWS_SECRET_ACCESS_KEY'), session_token: ENV['AWS_SESSION_TOKEN'])
    end
    selection = %w[TARGET SEED HEAD_LIMIT CENSUS_LIMIT REGISTRY_FLOOR REGISTRY_CAP].to_h { |key| [key.downcase.to_sym, ENV[key]] }.compact
    result = PackageCorpusExport.new(manifest: ENV['ASSIGNMENTS'], output: ENV.fetch('OUTPUT') { Rails.root.join('tmp', "package-corpus-#{Time.now.utc.strftime('%Y%m%dT%H%M%S%6N')}.tar.gz").to_s },
      source: ENV['SOURCE'], batch_size: ENV.fetch('BATCH_SIZE', '250'), **selection).run
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
