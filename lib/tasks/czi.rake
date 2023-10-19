require 'csv'

namespace :czi do
  task :bioconductor => :environment do
    # load csv file
    csv = CSV.read('data/bioconductor_raw_df.csv', headers: true)

    registry = Registry.find_by_ecosystem('bioconductor')

    file = File.open("data/bioconductor.ndjson", "a")

    processed_names = Set.new
    missing_names = Set.new
    dependencies = Set.new

    csv.each do |row|
      package = registry.packages.where('lower(name) = ?', row['Bioconductor Package'].downcase).first

      if package
        puts "#{package.name} - #{package.latest_release_number}"

        obj = package.as_json(include: [latest_version: { include: :dependencies }])
        
        file.puts JSON.generate(obj)

        processed_names << package.name
        package.latest_version.dependencies.map(&:package_name).each do |name|
          dependencies << name
        end
      else
        puts "Package not found: #{row['Bioconductor Package']}"
        missing_names << row['Bioconductor Package']
      end
    end

    while dependencies.count > 0

      first_level_dependencies = dependencies.flatten.uniq

      dependencies = Set.new

      first_level_dependencies.each do |name|
        next if processed_names.include?(name)
        next if missing_names.include?(name)
        package = registry.packages.where('lower(name) = ?', name.downcase).first
        if package
          puts "#{package.name} - #{package.latest_release_number}"

          obj = package.as_json(include: [latest_version: { include: :dependencies }])
          
          file.puts JSON.generate(obj)

          processed_names << package.name
          package.latest_version.dependencies.map(&:package_name).each do |name|
            dependencies << name
          end
        else
          puts "Package not found: #{name}"
          missing_names << name
        end
      end

      puts "Processed #{processed_names.uniq.count} packages"
      puts "Found #{missing_names.uniq.count} missing packages"
      puts "Found #{dependencies.uniq.count} dependencies"
      puts '--------------------------'
    end

    # TODO: look up missing packages, potentially fallback to CRAN

  end
end

