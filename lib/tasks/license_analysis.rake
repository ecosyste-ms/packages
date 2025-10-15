namespace :licenses do
  desc 'Analyze most frequent license values globally and per ecosystem'
  task analyze: :environment do
    top_registries_count = 9

    # Helper method to format arrays as comma-separated values
    def format_license(license)
      if license.is_a?(Array)
        if license.empty? || license == ['']
          'NULL'
        else
          license.join(', ')
        end
      elsif license.to_s.empty?
        'NULL'
      else
        license.to_s
      end
    end

    # Helper method to format numbers with commas
    def format_number(num)
      num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end

    puts "\n# License Field Analysis\n"
    puts "This is an extraction from the https://packages.ecosyste.ms/ service, analyzing the top 9 registries by package count and examining the most commonly used licenses across all active packages. This analysis uses the raw `licenses` field as reported by each package registry, with the analysis covering both the general package population and packages marked as critical infrastructure.\n"

    # Find top 9 registries by package count
    top_registries = Registry.order(packages_count: :desc).limit(top_registries_count)

    # Global analysis
    puts "\n## Global Analysis\n"

    total_packages = Package.active.count
    puts "Total packages: #{format_number(total_packages)}\n"

    puts "\n### Top licenses values:\n"
    global_licenses = Package.active
                               .group(:licenses)
                               .count
                               .sort_by { |_k, v| -v }
                               .first(20)

    puts "| License | Count | Percentage |"
    puts "|---------|-------|------------|"
    global_licenses.each do |(license, count)|
      percentage = (count.to_f / total_packages * 100).round(2)
      puts "| #{format_license(license)} | #{format_number(count)} | #{percentage}% |"
    end

    # Per registry analysis
    puts "\n## Per Registry Analysis\n"

    top_registries.each do |registry|
      reg_total = registry.packages.active.count

      puts "\n### #{registry.name} (#{registry.ecosystem})"
      puts "Total packages: #{format_number(reg_total)}\n"

      registry_licenses = registry.packages.active
                                    .group(:licenses)
                                    .count
                                    .sort_by { |_k, v| -v }
                                    .first(10)

      puts "\n#### Top licenses values:\n"
      puts "| License | Count | Percentage |"
      puts "|---------|-------|------------|"
      registry_licenses.each do |(license, count)|
        percentage = (count.to_f / reg_total * 100).round(2)
        puts "| #{format_license(license)} | #{format_number(count)} | #{percentage}% |"
      end
    end

    # Critical packages global analysis
    puts "\n## Critical Packages Global Analysis\n"

    critical_count = Package.active.critical.count
    puts "Total critical packages: #{format_number(critical_count)}\n"

    puts "\n### Top licenses values:\n"
    critical_licenses = Package.active
                            .critical
                            .group(:licenses)
                            .count
                            .sort_by { |_k, v| -v }
                            .first(10)

    puts "| License | Count | Percentage |"
    puts "|---------|-------|------------|"
    critical_licenses.each do |(license, count)|
      percentage = (count.to_f / critical_count * 100).round(2)
      puts "| #{format_license(license)} | #{format_number(count)} | #{percentage}% |"
    end

    # Critical packages per registry analysis
    puts "\n## Critical Packages Per Registry Analysis\n"

    top_registries.each do |registry|
      critical_total = registry.packages.active.critical.count

      puts "\n### #{registry.name} (#{registry.ecosystem})"
      puts "Total critical packages: #{format_number(critical_total)}\n"

      registry_critical_licenses = registry.packages.active
                                        .critical
                                        .group(:licenses)
                                        .count
                                        .sort_by { |_k, v| -v }
                                        .first(5)

      puts "\n#### Top licenses values:\n"
      puts "| License | Count | Percentage |"
      puts "|---------|-------|------------|"
      registry_critical_licenses.each do |(license, count)|
        percentage = (count.to_f / critical_total * 100).round(2)
        puts "| #{format_license(license)} | #{format_number(count)} | #{percentage}% |"
      end
    end

  end
end
