namespace :exports do
  desc 'Record export'
  task record: :environment do
    date = ENV['EXPORT_DATE'] || Date.today.strftime('%Y-%m-%d')
    bucket_name = ENV['BUCKET_NAME'] || 'ecosystems-data'
    Export.create!(date: date, bucket_name: bucket_name, packages_count: Package.count)
  end

  desc 'Export keywords data'
  task keywords: :environment do
    # list all packages with keywords
    packages = Package.where.not(keywords: [])
    # create a CSV file
    csv = CSV.generate do |csv|
      csv << %w[id ecosystem name description keywords]
      packages.find_each do |package|
        next unless package.description_with_fallback.present?
        description = package.description_with_fallback.gsub(/[\n\r]/, ' ')
        csv << [package.id, package.ecosystem, package.name, description, package.keywords.join('|')]
      end
    end
    
    # output the CSV file to stdout
    puts csv
  end

  desc 'export readme data'
  task readmes: :environment do
    registry = Registry.find_by(name: 'carthage')
    packages = Package.where(registry_id: registry.id).where.not(keywords: [])

    csv = CSV.generate do |csv|
      csv << %w[id ecosystem name normalized_licenses description readme keywords]
      packages.find_each do |package|
        readme = package.fetch_readme
        next unless readme.present? && readme['plain'].present?
        description = package.description_with_fallback.gsub(/[\n\r]/, ' ')
        csv << [package.id, package.ecosystem, package.name, package.normalized_licenses, description, readme['plain'], package.keywords.join('|')]
      end
    end
    
    # output the CSV file to stdout
    puts csv
  end
end