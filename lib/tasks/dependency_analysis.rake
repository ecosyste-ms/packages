namespace :dependency_analysis do
  desc "Research packages with dependency restrictions to identify breaking changes"
  desc "Usage: rake dependency_analysis:breaking_changes[critical_only,min_versions,ecosystem]"
  desc "  critical_only: 'true' to only analyze critical packages, 'false' for all (default: true)"
  desc "  min_versions: minimum number of versions required (default: 1)"
  desc "  ecosystem: ecosystem to analyze - cargo, npm, pypi, etc (default: cargo)"
  task :breaking_changes, [:critical_only, :min_versions, :ecosystem] => :environment do |t, args|
    critical_only = args[:critical_only] != 'false'
    min_versions = (args[:min_versions] || '1').to_i
    min_versions = 1 if min_versions < 1
    ecosystem = (args[:ecosystem] || 'cargo').downcase

    puts "Analyzing #{ecosystem.capitalize} packages with dependency restrictions..."
    puts "Parameters: critical_only=#{critical_only}, min_versions=#{min_versions}, ecosystem=#{ecosystem}"
    puts "=" * 80

    stage1_desc = critical_only ? "critical #{ecosystem.capitalize} packages" : "all #{ecosystem.capitalize} packages"
    puts "Stage 1: Finding #{stage1_desc} with #{min_versions}+ versions..."
    target_registry = Registry.find_by(ecosystem: ecosystem)
    unless target_registry
      puts "No #{ecosystem.capitalize} registry found!"
      return
    end

    packages_query = target_registry.packages.where("versions_count >= ?", min_versions)
    packages_query = packages_query.critical if critical_only

    packages = packages_query
    package_names = packages.pluck(:name)

    puts "Found #{packages.count} #{stage1_desc} with #{min_versions}+ versions:"
    puts

    puts "Stage 2: Searching for restrictive dependencies..."
    puts "(This may take a while as we process each dependency record...)"

    restrictive_deps = []
    total_processed = 0

    begin
      Dependency.ecosystem(ecosystem)
                .where(package_name: package_names)
                .joins(:version => :package)
                .select('dependencies.*, versions.number as version_number, packages.name as package_name_from_version')
                .each_row do |row|

        begin
          if restrictive_requirement?(row['requirements'])
            restrictive_deps << {
              target_package: row['package_name'],
              dependent_package: row['package_name_from_version'],
              dependent_version: row['version_number'],
              requirements: row['requirements'],
              restriction_type: categorize_restriction(row['requirements'])
            }
          end
        rescue => e
          puts "    WARNING: Error processing dependency row: #{e.message}"
          next
        end

        total_processed += 1
        puts "  Processed #{total_processed} dependency records..." if total_processed % 1000 == 0
      end
    rescue => e
      puts "ERROR: Failed to process dependencies: #{e.message}"
      puts "Aborting analysis."
      return
    end

    puts "Found #{restrictive_deps.count} dependencies with restrictive version ranges"
    puts

    puts "Stage 3: Identifying potential breaking change version pairs..."
    puts "-" * 50

    if restrictive_deps.empty?
      puts "No restrictive dependencies found."
    else
      breaking_change_candidates = []
      debug_count = 0
      processed_restrictions = 0
      total_restrictions = restrictive_deps.count

      restrictive_deps.each do |restriction|
        begin
          processed_restrictions += 1
          if processed_restrictions % 500 == 0
            puts "  Analyzed #{processed_restrictions}/#{total_restrictions} restrictive dependencies..."
          end

          target_pkg = target_registry.packages.find_by(name: restriction[:target_package])
          if !target_pkg
            debug_count += 1
            if debug_count <= 5
              puts "DEBUG: Package not found: #{restriction[:target_package]}"
            end
            next
          end

          restricted_version = extract_restricted_version(restriction[:requirements])
          if !restricted_version
            debug_count += 1
            if debug_count <= 5
              puts "DEBUG: Could not extract version from: #{restriction[:requirements]}"
            end
            next
          end

          available_versions = target_pkg.versions.pluck(:number).sort.reverse
          avoided_versions = available_versions.select do |v|
            begin
              is_version_avoided?(restriction[:requirements], v)
            rescue => e
              puts "    WARNING: Error checking if version #{v} is avoided by #{restriction[:requirements]}: #{e.message}"
              false
            end
          end

          if restricted_version && avoided_versions.any?
            breaking_change_candidates << {
              package_name: restriction[:target_package],
              restricted_to: restricted_version,
              next_avoided_version: avoided_versions.last, # The first version above the restriction
              latest_available: available_versions.first,
              avoided_versions_count: avoided_versions.count,
              restricting_package: restriction[:dependent_package],
              restricting_version: restriction[:dependent_version],
              restriction_pattern: restriction[:requirements],
              restriction_type: restriction[:restriction_type]
            }
          end
        rescue => e
          puts "    WARNING: Error processing restriction for #{restriction[:target_package]}: #{e.message}"
          next
        end
      end

      puts "  Completed analyzing all #{total_restrictions} restrictive dependencies."
      puts "  Found #{breaking_change_candidates.count} breaking change candidates."
      puts

      puts "Potential breaking change version pairs (v1 -> v2 where v2 broke compatibility):"
      puts

      # Group by target package and show version pairs
      breaking_change_candidates
        .group_by { |c| c[:package_name] }
        .sort_by { |name, candidates| -candidates.count }
        .first(15)
        .each_with_index do |(package_name, candidates), index|

          # Find the most common restricted version and its immediate next version
          restricted_versions = candidates.map { |c| c[:restricted_to] }.compact.tally
          most_restricted = restricted_versions.max_by { |v, count| count }

          # Find what's the first version being avoided
          sample_candidate = candidates.find { |c| c[:restricted_to] == most_restricted[0] }
          next_version = sample_candidate[:next_avoided_version]
          latest = sample_candidate[:latest_available]
          avoided_count = sample_candidate[:avoided_versions_count]

          puts "#{index + 1}. #{package_name}"
          puts "    Most restricted to: v#{most_restricted[0]} (#{most_restricted[1]} dependencies avoid newer versions)"
          puts "    First avoided version: v#{next_version} (likely introduced breaking change)"
          if avoided_count > 1
            puts "    Total avoided versions: #{avoided_count} (v#{next_version} through v#{latest})"
          end
          puts "    Potential breaking change: v#{most_restricted[0]} -> v#{next_version}"
          puts "    Dependencies avoiding upgrade:"

          # Group by restricting package to avoid duplicates
          restricting_candidates = candidates.select { |c| c[:restricted_to] == most_restricted[0] }
          unique_packages = restricting_candidates.group_by { |c| c[:restricting_package] }

          unique_packages.first(5).each do |pkg_name, pkg_candidates|
            versions = pkg_candidates.map { |c| c[:restricting_version] }.uniq.sort
            sample_pattern = pkg_candidates.first[:restriction_pattern]
            if versions.length == 1
              puts "      - #{pkg_name} v#{versions.first}: #{sample_pattern}"
            else
              puts "      - #{pkg_name} (#{versions.length} versions: v#{versions.first}..v#{versions.last}): #{sample_pattern}"
            end
          end

          remaining_packages = unique_packages.count - 5
          total_dependencies = restricting_candidates.count
          puts "      - ... and #{remaining_packages} more packages (#{total_dependencies} total dependencies)" if remaining_packages > 0
          puts
        end

      puts "Summary:"
      puts "Total packages with potential breaking changes: #{breaking_change_candidates.group_by { |c| c[:package_name] }.count}"
      puts "Total restrictive dependencies analyzed: #{restrictive_deps.count}"
    end

    puts
    puts "Stage 4: Analyzing requirement changes over version history..."
    puts "-" * 60

    requirement_changes = []

    breaking_change_candidates
      .group_by { |c| c[:package_name] }
      .sort_by { |name, candidates| -candidates.count }
      .first(10)
      .each do |package_name, candidates|

        puts "Analyzing #{package_name}..."

        candidates.group_by { |c| c[:restricting_package] }.each do |restricting_pkg_name, pkg_candidates|
          begin
            restricting_pkg = target_registry.packages.find_by(name: restricting_pkg_name)
            next unless restricting_pkg

            dep_history = Dependency.joins(:version)
                                   .where(versions: { package: restricting_pkg })
                                   .where(package_name: package_name)
                                   .includes(version: :package)
                                   .order('versions.published_at ASC NULLS LAST')

            if dep_history.count > 1
              requirements_over_time = dep_history.map do |dep|
                begin
                  {
                    version: dep.version.number,
                    published_at: dep.version.published_at,
                    requirements: dep.requirements
                  }
                rescue => e
                  puts "      WARNING: Error processing dependency history for #{dep.id}: #{e.message}"
                  nil
                end
              end.compact

              requirement_changes_found = []
              requirements_over_time.each_cons(2) do |prev, curr|
                begin
                  if prev[:requirements] != curr[:requirements]
                    requirement_changes_found << {
                      from_version: prev[:version],
                      to_version: curr[:version],
                      from_requirements: prev[:requirements],
                      to_requirements: curr[:requirements],
                      published_at: curr[:published_at]
                    }
                  end
                rescue => e
                  puts "      WARNING: Error comparing requirements: #{e.message}"
                  next
                end
              end

              if requirement_changes_found.any?
                requirement_changes << {
                  target_package: package_name,
                  restricting_package: restricting_pkg_name,
                  changes: requirement_changes_found,
                  total_versions: dep_history.count
                }
              end
            end
          rescue => e
            puts "    WARNING: Error processing requirement changes for #{restricting_pkg_name} -> #{package_name}: #{e.message}"
            next
          end
        end
      end

    puts
    if requirement_changes.empty?
      puts "No requirement changes found in version histories."
    else
      puts "Found packages that changed their requirements over time:"
      puts

      requirement_changes.each_with_index do |change, index|
        puts "#{index + 1}. #{change[:restricting_package]} -> #{change[:target_package]}"
        puts "   Total versions with dependency: #{change[:total_versions]}"
        puts "   Requirement changes:"

        change[:changes].each do |req_change|
          published = req_change[:published_at] ? req_change[:published_at].strftime('%Y-%m-%d') : 'unknown'
          puts "     v#{req_change[:from_version]} -> v#{req_change[:to_version]} (#{published})"
          puts "       #{req_change[:from_requirements]} -> #{req_change[:to_requirements]}"
        end
        puts
      end
    end

    puts
    puts "Stage 5: Generating Breaking Change Detection Report..."
    puts "=" * 70

    restriction_counts = breaking_change_candidates
      .group_by { |c| c[:package_name] }
      .transform_values { |candidates|
        {
          total_restrictions: candidates.count,
          unique_packages: candidates.map { |c| c[:restricting_package] }.uniq.count,
          candidates: candidates
        }
      }
      .sort_by { |name, data| -data[:total_restrictions] }

    puts "TOP 10 PACKAGES CAUSING MOST DEPENDENCY RESTRICTIONS"
    puts "=" * 55
    puts

    restriction_counts.first(10).each_with_index do |(package_name, data), index|
      sample_candidate = data[:candidates].first
      puts "#{index + 1}. #{package_name}"
      puts "   Breaking change: v#{sample_candidate[:restricted_to]} -> v#{sample_candidate[:next_avoided_version]}"
      puts "   Impact: #{data[:total_restrictions]} dependency restrictions across #{data[:unique_packages]} packages"

      related_changes = requirement_changes.select { |change| change[:target_package] == package_name }
      if related_changes.any?
        puts "   Evidence of breaking change:"
        evidence_count = 0
        related_changes.first(2).each do |change|
          change[:changes].first(3).each do |req_change|
            break if evidence_count >= 5
            published = req_change[:published_at] ? req_change[:published_at].strftime('%Y-%m-%d') : 'unknown'
            puts "     #{change[:restricting_package]} v#{req_change[:from_version]} -> v#{req_change[:to_version]} (#{published})"
            puts "       Requirement: #{req_change[:from_requirements]} -> #{req_change[:to_requirements]}"
            evidence_count += 1
          end
        end

        total_evidence = related_changes.sum { |c| c[:changes].count }
        if total_evidence > 5
          puts "     (#{total_evidence - 5} more requirement changes omitted)"
        end
      end
      puts
    end

    puts
    puts "DETAILED BREAKING CHANGE REPORT"
    puts "=" * 50
    puts

    restriction_counts.first(5).each do |package_name, data|
      puts "PACKAGE: #{package_name}"
      puts "-" * (package_name.length + 9)

      sample = data[:candidates].first
      puts "Suspected breaking version: v#{sample[:restricted_to]} -> v#{sample[:next_avoided_version]}"
      puts "Total dependency restrictions: #{data[:total_restrictions]}"
      puts "Packages affected: #{data[:unique_packages]}"
      puts

      puts "TIMELINE OF RESTRICTIONS:"
      version_timeline = data[:candidates]
        .group_by { |c| c[:restricting_package] }
        .map do |pkg_name, pkg_candidates|
          restricting_pkg = target_registry.packages.find_by(name: pkg_name)
          if restricting_pkg
            first_restrictive = Dependency.joins(:version)
              .where(versions: { package: restricting_pkg })
              .where(package_name: package_name)
              .where('requirements LIKE ?', "%#{sample[:restricted_to]}%")
              .includes(:version)
              .order('versions.published_at ASC')
              .first

            {
              package: pkg_name,
              first_restriction_version: first_restrictive&.version&.number,
              first_restriction_date: first_restrictive&.version&.published_at&.strftime('%Y-%m-%d'),
              restriction_pattern: sample[:restriction_pattern]
            }
          end
        end.compact.sort_by { |t| t[:first_restriction_date] || 'zzz' }

      version_timeline.first(5).each do |timeline|
        date = timeline[:first_restriction_date] || 'unknown'
        puts "  #{date}: #{timeline[:package]} v#{timeline[:first_restriction_version]} restricted to #{timeline[:restriction_pattern]}"
      end

      puts
      puts "REQUIREMENT EVOLUTION:"
      related_changes = requirement_changes.select { |change| change[:target_package] == package_name }
      if related_changes.any?
        related_changes.each do |change|
          significant_changes = change[:changes].select do |req_change|
            from_req = req_change[:from_requirements]
            to_req = req_change[:to_requirements]

            from_match = from_req.match(/\^?(\d+)/)
            to_match = to_req.match(/\^?(\d+)/)
            from_major = from_match ? from_match[1] : nil
            to_major = to_match ? to_match[1] : nil

            from_major != to_major ||
            from_req.start_with?('^') != to_req.start_with?('^') ||
            from_req.include?('=') != to_req.include?('=') ||
            from_req.include?('~') != to_req.include?('~') ||
            from_req.include?('<') != to_req.include?('<')
          end

          if significant_changes.any?
            puts "  #{change[:restricting_package]} (#{change[:total_versions]} versions):"
            puts "    Key requirement changes:"
            significant_changes.first(5).each do |req_change|
              published = req_change[:published_at] ? req_change[:published_at].strftime('%Y-%m-%d') : 'unknown'
              puts "      #{published}: v#{req_change[:from_version]} -> v#{req_change[:to_version]}"
              puts "        #{req_change[:from_requirements]} -> #{req_change[:to_requirements]}"
            end

            if change[:changes].count > significant_changes.count
              puts "      (#{change[:changes].count - significant_changes.count} minor version updates omitted)"
            end
          else
            puts "  #{change[:restricting_package]}: Only minor version updates, no significant pattern changes"
          end
        end
      else
        puts "  No requirement changes found (packages may have always restricted this version)"
      end

      puts
      puts "RECOMMENDATIONS:"
      if related_changes.any?
        puts "  HIGH CONFIDENCE: Breaking change detected via requirement evolution"
        puts "  First detected: #{related_changes.map { |c| c[:changes].map { |ch| ch[:published_at] } }.flatten.compact.min&.strftime('%Y-%m-%d')}"
        puts "  Action: Block automatic updates from v#{sample[:restricted_to]} to v#{sample[:next_avoided_version]}+"
        puts "  Suggest: Manual review required for this version transition"
      else
        puts "  MEDIUM CONFIDENCE: Multiple packages avoid this version but no evolution detected"
        puts "  Action: Flag for manual review before updating past v#{sample[:restricted_to]}"
      end

      puts
      puts "=" * 70
      puts
    end

    puts "SUMMARY FOR INTEGRATION"
    puts "=" * 35
    puts "High-confidence breaking changes detected: #{requirement_changes.count}"
    puts "Total packages analyzed: #{breaking_change_candidates.group_by { |c| c[:package_name] }.count}"
    puts "Packages with most restrictions: #{restriction_counts.first(10).map(&:first).join(', ')}"
    puts

    puts "Analysis complete!"
    puts "Total packages analyzed: #{packages.count}"
    puts "Total dependency records processed: #{total_processed}"
    puts "Restrictive dependencies found: #{restrictive_deps.count}"
    puts "Packages with requirement changes: #{requirement_changes.count}"
    puts "Most problematic packages identified: #{restriction_counts.count}"
  end

  desc "Test restrictive requirement detection with sample data"
  task test_restriction_detection: :environment do
    puts "Testing restrictive requirement detection..."

    test_cases = [
      "^1.0.0",      # Caret - somewhat restrictive
      "~1.0.0",      # Tilde - restrictive
      "=1.0.0",      # Exact - very restrictive
      ">=1.0.0",     # Not restrictive
      ">1.0.0",      # Not restrictive
      "<2.0.0",      # Restrictive upper bound
      "<=1.9.0",     # Restrictive upper bound
      ">=1.0.0, <2.0.0",  # Range with upper bound
      "*",           # Not restrictive
      "1.0.0"        # Exact (implicit =)
    ]

    test_cases.each do |req|
      result = restrictive_requirement?(req)
      type = categorize_restriction(req)
      puts "#{req.ljust(20)} => #{result ? 'RESTRICTIVE' : 'permissive'.upcase} (#{type})"
    end
  end

  private

  def restrictive_requirement?(requirements)
    begin
      return false if requirements.blank?
      return false if requirements == '*'  # Skip wildcard "any version"

      # Truly restrictive patterns that prevent automatic updates
      restrictive_patterns = [
        /^=\s*\d/,                    # Exact versions: =1.0.0, =2.4
        /^\d+\.\d+\.\d+$/,            # Implicit exact: 1.0.0
        /^~\d/,                       # Tilde ranges: ~1.0.0 (restrictive to patch level)
        /^<[=]?\s*\d/,                # Upper bounds: <2.0.0, <=1.9.0
        /^>=.*<[=]?\s*\d/,            # Bounded ranges: >=1.0.0, <2.0.0
        /^\d+(\.\d+)*\.\*(\.\*)*$/,   # Wildcard patterns: 1.*.*, 0.4.*
      ]

      # Skip caret ranges as they're designed to allow compatible updates
      # ^1.2.3 allows 1.2.4, 1.3.0, etc. - this is normal semver behavior
      return false if requirements.match?(/^\^\s*\d/)

      restrictive_patterns.any? { |pattern| requirements.match?(pattern) }
    rescue => e
      puts "    WARNING: Error checking if requirement #{requirements} is restrictive: #{e.message}"
      false
    end
  end

  def categorize_restriction(requirements)
    begin
      return "unknown" if requirements.blank?

      case requirements
      when /^=\s*\d/ then "exact_version"
      when /^\d+\.\d+\.\d+$/ then "implicit_exact"
      when /^~\d/ then "tilde_range"
      when /^<[=]?\s*\d/ then "upper_bound"
      when /^>=.*<[=]?\s*\d/ then "bounded_range"
      when /^\d+(\.\d+)*\.\*(\.\*)*$/ then "wildcard_pattern"
      when /^\^\s*\d/ then "caret_range_non_restrictive"  # Not actually restrictive
      else "other_restrictive"
      end
    rescue => e
      puts "    WARNING: Error categorizing requirement #{requirements}: #{e.message}"
      "unknown"
    end
  end

  def extract_restricted_version(requirements)
    begin
      return nil if requirements.blank?

      case requirements
      when /^=\s*(\d+(?:\.\d+)*(?:\.\d+)*)/ then $1                           # =2.4, =1.0.0, = 0.3.15
      when /^(\d+\.\d+\.\d+)$/ then $1                                         # 1.0.0
      when /^~(\d+(?:\.\d+)*(?:\.\d+)*)/ then $1                              # ~1, ~1.2, ~1.2.3, ~0.57, ~0
      when /^<[=]?\s*(\d+(?:\.\d+)*(?:\.\d+)*)/ then $1                      # <2.5, <=1.9.0, <=1.20
      when /^>=\s*(\d+(?:\.\d+)*(?:\.\d+)*),?\s*<[=]?\s*(\d+(?:\.\d+)*(?:\.\d+)*)/ then $1  # >=2, <2.5, >=1.3.0, <1.4.0
      when /^\^\s*(\d+(?:\.\d+)*(?:\.\d+)*)/ then $1                         # ^0.15.41, ^1, ^0.2
      when /^(\d+)(\.\d+)*\.\*(\.\*)*$/ then $1 + ($2 || '')                 # 1.*.*, 0.4.*, 0.7.* -> "1", "0.4", "0.7"
      when /^(\d+(?:\.\d+)*(?:\.\d+)*)-/ then $1                              # Pre-release versions: 0.10.0-rc.0
      when /^(\d+(?:\.\d+)*(?:\.\d+)*)-\w+/ then $1                           # Pre-release: 0.5.0-pre.1
      else
        # Try to extract any version number from the string as fallback
        version_match = requirements.match(/(\d+(?:\.\d+)*(?:\.\d+)*)/)
        version_match ? version_match[1] : nil
      end
    rescue => e
      puts "    WARNING: Error extracting version from #{requirements}: #{e.message}"
      nil
    end
  end

  def is_version_avoided?(requirements, available_version)
    return false if requirements.blank? || available_version.blank?

    begin
      case requirements
      when /^=\s*(\d+(?:\.\d+)*(?:\.\d+)*)/
        available_version != $1
      when /^(\d+\.\d+\.\d+)$/
        available_version != $1
      when /^~(\d+(?:\.\d+)*(?:\.\d+)*)/
        restricted_version = $1
        safe_version_compare(available_version, restricted_version) == 1
      when /^<[=]?\s*(\d+(?:\.\d+)*(?:\.\d+)*)/
        upper_bound = $1
        safe_version_compare(available_version, upper_bound) >= 0
      when /^>=\s*(\d+(?:\.\d+)*(?:\.\d+)*),?\s*<[=]?\s*(\d+(?:\.\d+)*(?:\.\d+)*)/
        lower, upper = $1, $2
        safe_version_compare(available_version, lower) == -1 || safe_version_compare(available_version, upper) >= 0
      else
        false
      end
    rescue => e
      # Log error but don't crash - just assume version is not avoided
      puts "    WARNING: Error comparing version #{available_version} with requirements #{requirements}: #{e.message}"
      false
    end
  end

  # Safe version comparison using semantic versioning when possible, fallback to string comparison
  def safe_version_compare(version1, version2)
    return 0 if version1 == version2

    begin
      # Try semantic version comparison first
      clean1 = SemanticRange.clean(version1) || version1
      clean2 = SemanticRange.clean(version2) || version2

      sem1 = Semantic::Version.new(clean1)
      sem2 = Semantic::Version.new(clean2)

      sem1 <=> sem2
    rescue ArgumentError
      # Fallback to string comparison if semantic parsing fails
      version1 <=> version2
    rescue => e
      # Final fallback - treat as equal if we can't compare
      puts "      WARNING: Could not compare #{version1} with #{version2}: #{e.message}"
      0
    end
  end
end