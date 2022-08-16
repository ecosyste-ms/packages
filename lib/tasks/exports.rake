namespace :exports do
  desc 'Record export'
  task record: :environment do
    Export.create!(date: ENV['EXPORT_DATE'], bucket_name: ENV['BUCKET_NAME'], packages_count: Package.count)
  end
end