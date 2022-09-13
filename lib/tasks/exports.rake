namespace :exports do
  desc 'Record export'
  task record: :environment do
    date = ENV['EXPORT_DATE'] || Date.today.strftime('%Y-%m-%d')
    bucket_name = ENV['BUCKET_NAME'] || 'ecosystems-data'
    Export.create!(date: date, bucket_name: bucket_name, packages_count: Package.count)
  end
end