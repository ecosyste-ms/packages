namespace :licenses do
  desc 'Analyze most frequent license values globally and per ecosystem'
  task analyze: :environment do
    limit = 20
    top_registries_count = 9

    # Helper method to format arrays as comma-separated values
    def format_license(license)
      if license.is_a?(Array)
        license.join(', ')
      else
        license.to_s
      end
    end

    # Helper method to format numbers with commas
    def format_number(num)
      num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end

    puts "\n# License Field Analysis\n"

    # Find top 9 registries by package count
    top_registries = Registry.order(packages_count: :desc).limit(top_registries_count)

    # Global analysis
    puts "\n## Global Analysis\n"

    total_packages = Package.active.count
    puts "Total packages: #{format_number(total_packages)}\n"

    puts "\n### Top #{limit} normalized_licenses values:\n"
    global_normalized = Package.active
                               .group(:normalized_licenses)
                               .count
                               .sort_by { |_k, v| -v }
                               .first(limit)

    global_normalized.each do |(license, count)|
      puts "- **#{format_license(license)}**: #{format_number(count)} packages"
    end

    # Per registry analysis
    puts "\n## Per Registry Analysis\n"

    top_registries.each do |registry|
      reg_total = registry.packages.active.count

      puts "\n### #{registry.name} (#{registry.ecosystem})"
      puts "Total packages: #{format_number(reg_total)}\n"

      registry_normalized = registry.packages.active
                                    .group(:normalized_licenses)
                                    .count
                                    .sort_by { |_k, v| -v }
                                    .first(limit)

      puts "\n#### Top #{limit} normalized_licenses values:\n"
      registry_normalized.each do |(license, count)|
        puts "- **#{format_license(license)}**: #{format_number(count)}"
      end
    end

    # Top 1% global analysis
    puts "\n## Top 1% Global Analysis\n"

    top_one_percent_count = Package.active.top(1).count
    puts "Total packages in top 1%: #{format_number(top_one_percent_count)}\n"

    puts "\n### Top #{limit} normalized_licenses values:\n"
    top_normalized = Package.active
                            .top(1)
                            .group(:normalized_licenses)
                            .count
                            .sort_by { |_k, v| -v }
                            .first(limit)

    top_normalized.each do |(license, count)|
      puts "- **#{format_license(license)}**: #{format_number(count)} packages"
    end

    # Top 1% per registry analysis
    puts "\n## Top 1% Per Registry Analysis\n"

    top_registries.each do |registry|
      top_reg_total = registry.packages.active.top(1).count

      puts "\n### #{registry.name} (#{registry.ecosystem})"
      puts "Total packages in top 1%: #{format_number(top_reg_total)}\n"

      registry_top_normalized = registry.packages.active
                                        .top(1)
                                        .group(:normalized_licenses)
                                        .count
                                        .sort_by { |_k, v| -v }
                                        .first(limit)

      puts "\n#### Top #{limit} normalized_licenses values:\n"
      registry_top_normalized.each do |(license, count)|
        puts "- **#{format_license(license)}**: #{format_number(count)}"
      end
    end

    puts "\n---\n**Analysis Complete**"
  end
end
