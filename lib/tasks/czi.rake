require 'csv'

namespace :czi do
  task :bioconductor => :environment do
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

    missing_names.each do |name|
      registry.sync_package_async(name)
    end


    # TODO: look up missing packages in old versions of registry, potentially fallback to CRAN

  end

  task :cran => :environment do
    csv = CSV.read('data/cran_raw_df.csv', headers: true)

    registry = Registry.find_by_ecosystem('cran')

    file = File.open("data/cran.ndjson", "a")

    processed_names = Set.new
    missing_names = Set.new
    dependencies = Set.new

    csv.each do |row|
      package = registry.packages.where(name: row['CRAN Package']).first
      package = registry.packages.where(name: row['CRAN Package'].downcase).first if package.nil?

      if package
        puts "#{package.name} - #{package.latest_release_number}"

        obj = package.as_json(include: [latest_version: { include: :dependencies }])
        
        next if package.latest_version.nil?

        file.puts JSON.generate(obj)

        processed_names << package.name
        package.latest_version.dependencies.map(&:package_name).each do |name|
          dependencies << name
        end
      else
        puts "Package not found: #{row['CRAN Package']}"
        missing_names << row['CRAN Package']
      end
    end

    while dependencies.count > 0

      first_level_dependencies = dependencies.flatten.uniq

      dependencies = Set.new

      first_level_dependencies.each do |name|
        next if processed_names.include?(name)
        next if missing_names.include?(name)
        package = registry.packages.where(name: name).first
        package = registry.packages.where(name: name.downcase).first if package.nil?

        if package
          puts "#{package.name} - #{package.latest_release_number}"

          obj = package.as_json(include: [latest_version: { include: :dependencies }])
          
          next if package.latest_version.nil?

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

    missing_names.each do |name|
      registry.sync_package_async(name)
    end
  end

  task :pypi => :environment do
    
    PEP_508_NAME_REGEX = /[A-Z0-9][A-Z0-9._-]*[A-Z0-9]|[A-Z0-9]/i.freeze
    PEP_508_NAME_WITH_EXTRAS_REGEX = /(^#{PEP_508_NAME_REGEX}\s*(?:\[#{PEP_508_NAME_REGEX}(?:,\s*#{PEP_508_NAME_REGEX})*\])?)/i.freeze

    def parse_pep_508_dep_spec(dep)
      name, requirement = dep.split(PEP_508_NAME_WITH_EXTRAS_REGEX, 2).last(2)
      version, environment_markers = requirement.split(";").map(&:strip)

      # remove whitespace from name
      # remove parentheses surrounding version requirement
      [name.remove(/\s/), version&.remove(/[()]/) || "", environment_markers || ""]
    end

    csv = CSV.read('data/pypi_raw_df.csv', headers: true)

    registry = Registry.find_by_ecosystem('pypi')

    file = File.open("data/pypi.ndjson", "a")

    processed_names = Set.new
    missing_names = Set.new
    dependencies = Set.new

    csv.each do |row|
      package = registry.packages.where(name: row['pypi package']).first
      package = registry.packages.where(name: row['pypi package'].downcase).first if package.nil?
      package = registry.packages.where(name: row['pypi package'].downcase.gsub('_', '-')).first if package.nil?

      if package
        puts "#{package.name} - #{package.latest_release_number}"

        obj = package.as_json(include: [latest_version: { include: :dependencies }])
        
        next if package.latest_version.nil?

        file.puts JSON.generate(obj)

        processed_names << package.name
        package.latest_version.dependencies.map(&:package_name).each do |name|
          n,v,e = parse_pep_508_dep_spec(name)
          n = n.split('[').first if n.include?('[') # extras
          dependencies << n
        end
      else
        puts "Package not found: #{row['pypi package']}"
        missing_names << row['pypi package']
      end
    end

    while dependencies.count > 0

      first_level_dependencies = dependencies.flatten.uniq

      dependencies = Set.new

      first_level_dependencies.each do |name|
        next if processed_names.include?(name)
        next if missing_names.include?(name)
        next if processed_names.include?(name.downcase)
        next if processed_names.include?(name.downcase)

        package = registry.packages.where(name: name).first
        package = registry.packages.where(name: name.downcase).first if package.nil?
        package = registry.packages.where(name: name.downcase.gsub('_', '-')).first if package.nil?
        if package
          puts "#{package.name} - #{package.latest_release_number}"

          obj = package.as_json(include: [latest_version: { include: :dependencies }])
          
          next if package.latest_version.nil?

          file.puts JSON.generate(obj)

          processed_names << package.name
          package.latest_version.dependencies.map(&:package_name).each do |name|
            n,v,e = parse_pep_508_dep_spec(name)
            n = n.split('[').first if n.include?('[') # extras
            dependencies << n
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

    missing_names.each do |name|
      puts name
      # registry.sync_package_async(name)
    end
  end
end

