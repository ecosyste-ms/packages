namespace :ncsu do
  desc "Verify NCSU PhD student package counts. Usage: ECOSYSTEM=npm rake ncsu:verify_counts"
  task verify_counts: :environment do
    two_years_before_cutoff = Date.new(2023, 10, 4)
    recent_release_cutoff = Date.new(2023, 10, 4)

    ecosystem_name = ENV.fetch('ECOSYSTEM') { abort "Usage: ECOSYSTEM=npm rake ncsu:verify_counts" }

    registry = Registry.find_by(ecosystem: ecosystem_name)
    abort "Registry not found for #{ecosystem_name}" unless registry

    base = registry.packages.active

    # Step 1: Packages at least two years old (first release before Oct 4, 2023)
    print "Step 1: fetching old packages..."
    step1_ids = base.where("first_release_published_at <= ?", two_years_before_cutoff).pluck(:id)
    puts " #{step1_ids.length}"

    # Step 2: Packages with GitHub repositories
    print "Step 2: filtering GitHub repos..."
    step2_ids = []
    step1_ids.each_slice(100).with_index do |batch, i|
      print "\rStep 2: filtering GitHub repos... #{i * 100}/#{step1_ids.length}"
      ids = Package.where(id: batch)
                   .where("repository_url ILIKE '%github.com%'")
                   .pluck(:id)
      step2_ids.concat(ids)
    end
    puts "\rStep 2: filtering GitHub repos... #{step2_ids.length}                    "

    # Step 3: Packages with at least one dependent AND at least one dependency (on latest version)
    print "Step 3a: filtering packages with dependents..."
    step2_with_dependents = []
    step2_ids.each_slice(100).with_index do |batch, i|
      print "\rStep 3a: filtering packages with dependents... #{i * 100}/#{step2_ids.length}"
      ids = Package.where(id: batch)
                   .where("dependent_packages_count > 0")
                   .pluck(:id)
      step2_with_dependents.concat(ids)
    end
    puts "\rStep 3a: filtering packages with dependents... #{step2_with_dependents.length}                    "

    print "Step 3b: checking for dependencies and loading package data..."
    step3_ids = []
    step2_with_dependents.each_slice(100).with_index do |batch, i|
      print "\rStep 3b: checking for dependencies... #{i * 100}/#{step2_with_dependents.length}"
      packages_with_deps = Version.where(package_id: batch, latest: true)
                                  .joins(:dependencies)
                                  .distinct
                                  .pluck(:package_id)
      step3_ids.concat(packages_with_deps)
    end
    puts "\rStep 3b: checking for dependencies... #{step3_ids.length}                    "

    # Load all package data we need for steps 4, 5, 6
    print "Step 3c: loading package data..."
    packages_data = {}
    step3_ids.each_slice(100).with_index do |batch, i|
      print "\rStep 3c: loading package data... #{i * 100}/#{step3_ids.length}"
      Package.where(id: batch)
             .select(:id, :repository_url, :repo_metadata, :latest_release_number, :latest_release_published_at)
             .each do |pkg|
        packages_data[pkg.id] = {
          repository_url: pkg.repository_url&.downcase,
          repo_metadata: pkg.repo_metadata,
          latest_release_number: pkg.latest_release_number,
          latest_release_published_at: pkg.latest_release_published_at
        }
      end
    end
    puts "\rStep 3c: loading package data... #{packages_data.length}                    "

    # Step 4: GitHub repositories that map to a single package
    print "Step 4: finding single-package repos..."
    repo_package_counts = Hash.new(0)
    packages_data.each do |id, data|
      next if data[:repository_url].blank?
      repo_package_counts[data[:repository_url]] += 1
    end

    single_repos = repo_package_counts.select { |_repo, count| count == 1 }.keys.to_set
    step4_ids = packages_data.select { |_id, data| data[:repository_url].present? && single_repos.include?(data[:repository_url]) }.keys
    puts " #{step4_ids.length}"

    # Step 5: Packages where release tag name matches a tag name in repo
    print "Step 5: checking release/tag matches..."
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
    puts " #{step5_ids.length}"

    # Step 6: Packages with releases in past 2 years (as of Oct 4, 2025)
    print "Step 6: checking for recent releases..."
    step6_ids = step5_ids.select do |id|
      data = packages_data[id]
      data[:latest_release_published_at] && data[:latest_release_published_at] >= recent_release_cutoff
    end
    puts " #{step6_ids.length}"

    # Step 7: Packages with more than one release in past 2 years
    print "Step 7: checking for multiple releases..."
    step7_ids = []
    step6_ids.each_slice(100).with_index do |batch, i|
      print "\rStep 7: checking for multiple releases... #{i * 100}/#{step6_ids.length}"
      counts = Version.where(package_id: batch)
                      .where("published_at >= ?", recent_release_cutoff)
                      .group(:package_id)
                      .count
      counts.each do |pkg_id, count|
        step7_ids << pkg_id if count > 1
      end
    end
    puts "\rStep 7: checking for multiple releases... #{step7_ids.length}                    "

    puts "\n=== #{ecosystem_name.upcase} RESULTS ==="
    puts "Step 1 (at least 2 years old): #{step1_ids.length}"
    puts "Step 2 (with GitHub repos): #{step2_ids.length}"
    puts "Step 3 (has dependent and dependency): #{step3_ids.length}"
    puts "Step 4 (single package per repo): #{step4_ids.length}"
    puts "Step 5 (release tag matches tag name): #{step5_ids.length}"
    puts "Step 6 (releases in past 2 years): #{step6_ids.length}"
    puts "Step 7 (more than one release in past 2 years): #{step7_ids.length}"
  end
end
