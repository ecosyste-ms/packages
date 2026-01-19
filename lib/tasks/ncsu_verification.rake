require 'csv'

namespace :ncsu do
  TWO_YEARS_BEFORE_CUTOFF = Date.new(2023, 10, 4)
  RECENT_RELEASE_CUTOFF = Date.new(2023, 10, 4)

  def self.filter_packages(ecosystem_name, output: $stdout)
    registry = Registry.find_by(ecosystem: ecosystem_name)
    abort "Registry not found for #{ecosystem_name}" unless registry

    base = registry.packages.active

    # Step 1: Packages at least two years old (first release before Oct 4, 2023)
    output.print "Step 1: fetching old packages..."
    step1_ids = base.where("first_release_published_at <= ?", TWO_YEARS_BEFORE_CUTOFF).pluck(:id)
    output.puts " #{step1_ids.length}"

    # Step 2: Packages with GitHub repositories
    output.print "Step 2: filtering GitHub repos..."
    step2_ids = []
    step1_ids.each_slice(100).with_index do |batch, i|
      output.print "\rStep 2: filtering GitHub repos... #{i * 100}/#{step1_ids.length}"
      ids = Package.where(id: batch)
                   .where("repository_url ILIKE '%github.com%'")
                   .pluck(:id)
      step2_ids.concat(ids)
    end
    output.puts "\rStep 2: filtering GitHub repos... #{step2_ids.length}                    "

    # Step 3: Packages with at least one dependent AND at least one dependency (on latest version)
    output.print "Step 3a: filtering packages with dependents..."
    step2_with_dependents = []
    step2_ids.each_slice(100).with_index do |batch, i|
      output.print "\rStep 3a: filtering packages with dependents... #{i * 100}/#{step2_ids.length}"
      ids = Package.where(id: batch)
                   .where("dependent_packages_count > 0")
                   .pluck(:id)
      step2_with_dependents.concat(ids)
    end
    output.puts "\rStep 3a: filtering packages with dependents... #{step2_with_dependents.length}                    "

    # Step 3b: Check which packages have dependencies on their latest version
    # First batch fetch all version IDs
    output.print "Step 3b: fetching version IDs..."
    pkg_to_version = {}
    step2_with_dependents.each_slice(1000).with_index do |batch, i|
      output.print "\rStep 3b: fetching version IDs... #{i * 1000}/#{step2_with_dependents.length}"
      output.flush
      Version.where(package_id: batch, latest: true).pluck(:package_id, :id).each do |pkg_id, version_id|
        pkg_to_version[pkg_id] = version_id
      end
    end
    output.puts "\rStep 3b: fetching version IDs... #{pkg_to_version.length}                    "

    # Then batch check which versions have dependencies
    output.print "Step 3b: checking for dependencies..."
    step3_ids = []
    version_to_pkg = pkg_to_version.invert
    pkg_to_version.values.each_slice(1000).with_index do |batch, i|
      output.print "\rStep 3b: checking for dependencies... #{i * 1000}/#{pkg_to_version.length}"
      output.flush
      Dependency.where(version_id: batch).distinct.pluck(:version_id).each do |version_id|
        step3_ids << version_to_pkg[version_id]
      end
    end
    output.puts "\rStep 3b: checking for dependencies... #{step3_ids.length}                    "

    # Load all package data we need for steps 4, 5, 6
    output.print "Step 3c: loading package data..."
    packages_data = {}
    step3_ids.each_slice(100).with_index do |batch, i|
      output.print "\rStep 3c: loading package data... #{i * 100}/#{step3_ids.length}"
      Package.where(id: batch)
             .select(:id, :name, :repository_url, :repo_metadata, :latest_release_number, :latest_release_published_at)
             .each do |pkg|
        packages_data[pkg.id] = {
          name: pkg.name,
          repository_url: pkg.repository_url&.downcase,
          repo_metadata: pkg.repo_metadata,
          latest_release_number: pkg.latest_release_number,
          latest_release_published_at: pkg.latest_release_published_at
        }
      end
    end
    output.puts "\rStep 3c: loading package data... #{packages_data.length}                    "

    # Step 4: GitHub repositories that map to a single package
    output.print "Step 4: finding single-package repos..."
    repo_package_counts = Hash.new(0)
    packages_data.each do |id, data|
      next if data[:repository_url].blank?
      repo_package_counts[data[:repository_url]] += 1
    end

    single_repos = repo_package_counts.select { |_repo, count| count == 1 }.keys.to_set
    step4_ids = packages_data.select { |_id, data| data[:repository_url].present? && single_repos.include?(data[:repository_url]) }.keys
    output.puts " #{step4_ids.length}"

    # Step 5: Packages where release tag name matches a tag name in repo
    output.print "Step 5: checking release/tag matches..."
    step5_ids = []
    step4_ids.each do |id|
      data = packages_data[id]
      tags = data[:repo_metadata]&.dig('tags')
      next unless tags.is_a?(Array) && tags.any?

      latest_version = data[:latest_release_number]
      next unless latest_version.present?

      tag_names = tags.map { |t| t['name'] }
      if tag_names.include?(latest_version) || tag_names.include?("v#{latest_version}") ||
         tag_names.include?(latest_version.delete_prefix('v'))
        step5_ids << id
      end
    end
    output.puts " #{step5_ids.length}"

    # Step 6: Packages with releases in past 2 years (as of Oct 4, 2025)
    output.print "Step 6: checking for recent releases..."
    step6_ids = step5_ids.select do |id|
      data = packages_data[id]
      data[:latest_release_published_at] && data[:latest_release_published_at] >= RECENT_RELEASE_CUTOFF
    end
    output.puts " #{step6_ids.length}"

    # Step 7: Packages with more than one release in past 2 years
    output.print "Step 7: checking for multiple releases..."
    step7_ids = []
    step6_ids.each_slice(100).with_index do |batch, i|
      output.print "\rStep 7: checking for multiple releases... #{i * 100}/#{step6_ids.length}"
      counts = Version.where(package_id: batch)
                      .where("published_at >= ?", RECENT_RELEASE_CUTOFF)
                      .group(:package_id)
                      .count
      counts.each do |pkg_id, count|
        step7_ids << pkg_id if count > 1
      end
    end
    output.puts "\rStep 7: checking for multiple releases... #{step7_ids.length}                    "

    {
      step1_ids: step1_ids,
      step2_ids: step2_ids,
      step3_ids: step3_ids,
      step4_ids: step4_ids,
      step5_ids: step5_ids,
      step6_ids: step6_ids,
      step7_ids: step7_ids,
      packages_data: packages_data
    }
  end

  desc "Verify NCSU PhD student package counts. Usage: rake ncsu:verify_counts[npm]"
  task :verify_counts, [:ecosystem] => :environment do |_t, args|
    ecosystem_name = args[:ecosystem] || abort("Usage: rake ncsu:verify_counts[npm]")

    results = filter_packages(ecosystem_name)

    puts "\n=== #{ecosystem_name.upcase} RESULTS ==="
    puts "Step 1 (at least 2 years old): #{results[:step1_ids].length}"
    puts "Step 2 (with GitHub repos): #{results[:step2_ids].length}"
    puts "Step 3 (has dependent and dependency): #{results[:step3_ids].length}"
    puts "Step 4 (single package per repo): #{results[:step4_ids].length}"
    puts "Step 5 (release tag matches tag name): #{results[:step5_ids].length}"
    puts "Step 6 (releases in past 2 years): #{results[:step6_ids].length}"
    puts "Step 7 (more than one release in past 2 years): #{results[:step7_ids].length}"
  end

  desc "Export package names and GitHub URLs. Usage: rake ncsu:export_packages[npm,packages.csv]"
  task :export_packages, [:ecosystem, :output] => :environment do |_t, args|
    ecosystem_name = args[:ecosystem] || abort("Usage: rake ncsu:export_packages[npm,packages.csv]")
    output_file = args[:output] || abort("Usage: rake ncsu:export_packages[npm,packages.csv]")

    results = filter_packages(ecosystem_name)
    packages_data = results[:packages_data]
    final_ids = results[:step7_ids]

    puts "\nExporting #{final_ids.length} packages to #{output_file}..."

    CSV.open(output_file, 'w') do |csv|
      csv << ['package_name', 'repository_url']
      final_ids.each do |id|
        data = packages_data[id]
        csv << [data[:name], data[:repository_url]]
      end
    end

    puts "Done. Exported #{final_ids.length} packages."
  end

  desc "Export CSV to stdout (for piping via dokku). Usage: dokku run packages rake ncsu:export_csv[npm] > packages.csv"
  task :export_csv, [:ecosystem] => :environment do |_t, args|
    ecosystem_name = args[:ecosystem] || abort("Usage: rake ncsu:export_csv[npm]")

    results = filter_packages(ecosystem_name, output: $stderr)
    packages_data = results[:packages_data]
    final_ids = results[:step7_ids]

    $stderr.puts "\nExporting #{final_ids.length} packages..."

    puts CSV.generate_line(['package_name', 'repository_url'])
    final_ids.each do |id|
      data = packages_data[id]
      puts CSV.generate_line([data[:name], data[:repository_url]])
    end

    $stderr.puts "Done."
  end
end
