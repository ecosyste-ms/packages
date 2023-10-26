require 'csv'

namespace :czi do
  task :bioconductor => :environment do
    csv = CSV.read('data/bioconductor_df.csv', headers: true)

    mention_counts_file = File.read("data/comm_disambiguated_ids_count.json")
    mention_counts = JSON.parse(mention_counts_file)

    registry = Registry.find_by_ecosystem('bioconductor')

    file = File.open("data/bioconductor_with_mention_counts.ndjson", "a")

    processed_names = Set.new
    missing_names = Set.new
    dependencies = Set.new

    csv.each do |row|
      package = registry.packages.where('lower(name) = ?', row['software_mention'].downcase).first

      if package
        puts "#{package.name} - #{package.latest_release_number}"

        obj = package.as_json(include: [:maintainers,latest_version: { include: :dependencies }])
        obj['mentioned'] = true
        
        mentions = mention_counts[row['ID']]
        obj['mentions_count'] = mentions
        obj['czi_id'] = row['ID']

        file.puts JSON.generate(obj)

        processed_names << package.name
        package.latest_version.dependencies.map(&:package_name).each do |name|
          dependencies << name
        end
      else
        puts "Package not found: #{row['software_mention']}"
        missing_names << row['software_mention']
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

          obj = package.as_json(include: [:maintainers, latest_version: { include: :dependencies }])
          obj['mentioned'] = false
          obj['mentions_count'] = 0
          obj['czi_id']

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

  task :cran => :environment do
    csv = CSV.read('data/cran_df.csv', headers: true)

    mention_counts_file = File.read("data/comm_disambiguated_ids_count.json")
    mention_counts = JSON.parse(mention_counts_file)

    registry = Registry.find_by_ecosystem('cran')

    file = File.open("data/cran_with_mention_counts.ndjson", "a")

    processed_names = Set.new
    missing_names = Set.new
    dependencies = Set.new

    csv.each do |row|
      package = registry.packages.where(name: row['software_mention']).first
      package = registry.packages.where(name: row['software_mention'].downcase).first if package.nil?

      if package
        puts "#{package.name} - #{package.latest_release_number}"
        
        next if package.latest_version.nil?

        obj = package.as_json(include: [:maintainers,latest_version: { include: :dependencies }])
        obj['mentioned'] = true
        mentions = mention_counts[row['ID']]
        obj['mentions_count'] = mentions
        obj['czi_id'] = row['ID']

        file.puts JSON.generate(obj)

        processed_names << package.name
        package.latest_version.dependencies.map(&:package_name).each do |name|
          dependencies << name
        end
      else
        puts "Package not found: #{row['software_mention']}"
        missing_names << row['software_mention']
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

          next if package.latest_version.nil?

          obj = package.as_json(include: [:maintainers,latest_version: { include: :dependencies }])
          obj['mentioned'] = false
          obj['mentions_count'] = 0
          obj['czi_id'] = nil

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

    def normalized_name(name)
      name.downcase.gsub('_', '-').gsub('.', '-')
    end

    csv = CSV.read('data/pypi_raw_df.csv', headers: true)

    registry = Registry.find_by_ecosystem('pypi')

    file = File.open("data/pypi.ndjson", "a")

    processed_names = Set.new
    missing_names = Set.new
    dependencies = Set.new

    csv.each do |row|
      package = registry.packages.find_by_name(row['pypi package'])
      package = registry.packages.find_by_normalized_name(row['pypi package']) if package.nil? && row['pypi package'] != normalized_name(row['pypi package'])

      if package
        puts "#{package.name} - #{package.latest_release_number}"

        obj = package.as_json(include: [latest_version: { include: :dependencies }])
        
        next if package.latest_version.nil?

        file.puts JSON.generate(obj)

        processed_names << normalized_name(package.name)
        package.latest_version.dependencies.map(&:package_name).each do |name|
          n,v,e = parse_pep_508_dep_spec(name)
          n = n.split('[').first if n.include?('[') # extras
          dependencies << normalized_name(n)
        end
      else
        puts "Package not found: #{row['pypi package']}"
        missing_names << normalized_name(row['pypi package'])
      end
    end

    while dependencies.count > 0

      first_level_dependencies = dependencies.flatten.uniq

      dependencies = Set.new

      first_level_dependencies.each do |name|
        next if processed_names.include?(normalized_name(name))
        next if missing_names.include?(normalized_name(name))

        package = registry.packages.find_by_name(name)
        package = registry.packages.find_by_normalized_name(name) if package.nil? && name != normalized_name(name)
        
        if package
          puts "#{package.name} - #{package.latest_release_number}"

          obj = package.as_json(include: [latest_version: { include: :dependencies }])
          
          next if package.latest_version.nil?

          file.puts JSON.generate(obj)

          processed_names << normalized_name(package.name)
          package.latest_version.dependencies.map(&:package_name).each do |name|
            n,v,e = parse_pep_508_dep_spec(name)
            n = n.split('[').first if n.include?('[') # extras
            dependencies << normalized_name(n)
          end
        else
          puts "Package not found: #{name}"
          missing_names << normalized_name(name)
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

  task github: :environment do
    file = File.open("data/github_packages.ndjson", "a")

    packages = Set.new
    github_urls = Set.new

    CSV.foreach('data/github_df.csv', headers: true) do |row|
      github_urls << row['package_url'].downcase
      print '.'
    end;nil

    github_urls.to_a.sort.each do |url|
      puts url
      Package.repository_url(url).each do |package|
        packages << [package.ecosystem, package.name, package.id]
      end
    end

    packages.each do |ecosystem, name, id|
      package = Package.find(id)
      puts "  #{package.ecosystem} - #{package.name} - #{package.latest_release_number}"
  
      next if package.latest_version.nil?

      obj = package.as_json(include: [latest_version: { include: :dependencies }])

      file.puts JSON.generate(obj)
    end

    # todo fetch transitive dependencies of each discovered package

  end

  task github_with_transitive: :environment do

    PEP_508_NAME_REGEX = /[A-Z0-9][A-Z0-9._-]*[A-Z0-9]|[A-Z0-9]/i.freeze
    PEP_508_NAME_WITH_EXTRAS_REGEX = /(^#{PEP_508_NAME_REGEX}\s*(?:\[#{PEP_508_NAME_REGEX}(?:,\s*#{PEP_508_NAME_REGEX})*\])?)/i.freeze

    def parse_pep_508_dep_spec(dep)
      name, requirement = dep.split(PEP_508_NAME_WITH_EXTRAS_REGEX, 2).last(2)
      version, environment_markers = requirement.split(";").map(&:strip)

      # remove whitespace from name
      # remove parentheses surrounding version requirement
      [name.remove(/\s/), version&.remove(/[()]/) || "", environment_markers || ""]
    end

    def normalized_name(name)
      name.downcase.gsub('_', '-').gsub('.', '-')
    end

    file = File.open("data/github_packages_with_transitive.ndjson", "a")

    packages = Set.new
    github_urls = Set.new
    
    processed_names = Set.new
    missing_names = Set.new
    dependencies = Set.new

    CSV.foreach('data/github_df.csv', headers: true) do |row|
      github_urls << row['package_url'].downcase
      print '.'
    end;nil

    github_urls.to_a.sort.each do |url|
      puts url
      Package.repository_url(url).each do |package|
        packages << [package.ecosystem, package.name, package.id]
      end
    end

    packages.each do |ecosystem, name, id|
      package = Package.find(id)
      puts "  #{package.ecosystem} - #{package.name} - #{package.latest_release_number}"
  
      next if package.latest_version.nil?

      obj = package.as_json(include: [latest_version: { include: :dependencies }])

      file.puts JSON.generate(obj)

      if package.ecosystem == 'pypi'
        name = normalized_name(package.name)
      else
        name = package.name.downcase
      end

      processed_names << [package.registry_id, name]
      package.latest_version.dependencies.map(&:package_name).each do |dep_name|
        if package.ecosystem == 'pypi'
          n,v,e = parse_pep_508_dep_spec(dep_name)
          n = n.split('[').first if n.include?('[') # extras
          dependencies << [package.registry_id, normalized_name(n)]
        else
          dependencies << [package.registry_id, dep_name.downcase]
        end
      end
    end

    while dependencies.count > 0

      first_level_dependencies = dependencies.flatten.uniq

      dependencies = Set.new

      first_level_dependencies.each do |registry_id, name|
        next if processed_names.include?([registry_id, name.downcase])
        next if missing_names.include?([registry_id, name.downcase])

        registry = Registry.find(registry_id)
        package = registry.packages.find_by_name(name)
        package = registry.packages.find_by_normalized_name(name) if registry.ecosystem == 'pypi' && package.nil? && name != normalized_name(name)
        
        if package
          puts "#{package.name} - #{package.latest_release_number}"

          obj = package.as_json(include: [latest_version: { include: :dependencies }])
          
          next if package.latest_version.nil?

          file.puts JSON.generate(obj)

          if package.ecosystem == 'pypi'
            name = normalized_name(package.name)
          else
            name = package.name.downcase
          end

          processed_names << [package.registry_id, name]
          package.latest_version.dependencies.map(&:package_name).each do |dep_name|
            if package.ecosystem == 'pypi'
              n,v,e = parse_pep_508_dep_spec(dep_name)
              n = n.split('[').first if n.include?('[') # extras
              dependencies << [package.registry_id, normalized_name(n)]
            else
              dependencies << [package.registry_id, dep_name]
            end
          end
        else
          puts "Package not found: #{name}"
          missing_names << [registry_id, name.downcase]
        end
      end

      puts "Processed #{processed_names.uniq.count} packages"
      puts "Found #{missing_names.uniq.count} missing packages"
      puts "Found #{dependencies.uniq.count} dependencies"
      puts '--------------------------'
    end

  end

  # task bioconductor_commits: :environment do
  #   # ping the commits service for each package's git repo 
  #   # and store the commit sha in the package's latest version
  #   registry = Registry.find_by_ecosystem('bioconductor')

  #   file = File.open("data/bioconductor_commits.ndjson", "a")

  #   count = 0

  #   registry.packages.each do |package|
  #     next if package.repository_url.blank?

  #     puts package.name

  #     connection = Faraday.new 'https://commits.ecosyste.ms' do |builder|
  #       builder.use Faraday::FollowRedirects::Middleware
  #       builder.request :retry, { max: 5, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2 }
  #       builder.response :json
  #       builder.request :json
  #       builder.request :instrumentation
  #       builder.adapter Faraday.default_adapter, accept_encoding: "gzip"
  #     end

  #     url = "/api/v1/repositories/lookup?url=#{package.repository_url}"
  #     puts url
  #     response = connection.get(url)
  #     if response.status == 200
        
  #       json = response.body
  #       p json
  #       obj = package.as_json(include: :maintainers)
  #       obj['commits_stats'] = json

  #       file.puts JSON.generate(obj)
  #     elsif response.status == 404
  #       puts "Error: #{response.status}"
  #     end
  #   end
  # end

  task :count_ids => :environment do
    ids = {}
    total = 14770210
    CSV.foreach('data/comm_disambiguated.tsv', headers: true, col_sep: "\t") do |row| 
      print " row: #{$.} (#{$./total.to_f*100}%) \r"
      ids[row['ID']] ||= 0
      ids[row['ID']] += 1
    end
    
    puts ""
    puts "Total: #{ids.values.sum}"
    puts "Unique IDs: #{ids.keys.count}"
    puts "Average: #{ids.values.sum / ids.keys.count}"
    puts "Top 10:"
    ids.sort_by{|k,v| v}.reverse.first(10).each do |k,v|
      puts "#{k}: #{v}"
    end

    json = File.open("data/comm_disambiguated_ids_count.json", "w")
    json << JSON.pretty_generate(ids)
    json.close

    # output = File.open("data/comm_disambiguated_ids_count.csv", "w")
    # output << "ID,Count\n"
    # ids.each do |k,v|
    #   output << "#{k},#{v}\n"
    # end
    # output.close

  end
end

