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
      packages.each_instance do |package|
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
      packages.each_instance do |package|
        readme = package.fetch_readme
        next unless readme.present? && readme['plain'].present?
        description = package.description_with_fallback.to_s.gsub(/[\n\r]/, ' ')
        csv << [package.id, package.ecosystem, package.name, package.normalized_licenses.join('|'), description, readme['plain'], package.keywords.join('|')]
      end
    end

    # output the CSV file to stdout
    puts csv
  end

  desc 'Export top packages with licenses to CSV (usage: rake exports:licenses PERCENT=1)'
  task licenses: :environment do
    percent = ENV['PERCENT']&.to_f || 1.0

    puts CSV.generate_line(['ecosystem', 'name', 'licenses'])

    Package
      .active
      .top(percent)
      .select(:ecosystem, :name, :licenses)
      .each_row do |row|
        puts CSV.generate_line([row['ecosystem'], row['name'], row['licenses']])
      end
  end

  desc 'Export top packages to CSV (usage: rake exports:packages PERCENT=1 ECOSYSTEM=npm)'
  task packages: :environment do
    percent = ENV['PERCENT']&.to_f || 1.0
    ecosystem = ENV['ECOSYSTEM']

    puts CSV.generate_line([
      'package_id', 'name', 'ecosystem', 'description', 'homepage', 'licenses',
      'repository_url', 'versions_count', 'first_release_published_at',
      'latest_release_published_at', 'metadata',
      'dependent_packages_count', 'downloads', 'rankings'
    ])

    scope = Package.active.top(percent)
    if ecosystem.present?
      registry = Registry.where(ecosystem: ecosystem, default: true).first
      scope = scope.where(registry_id: registry.id) if registry
    end

    scope
      .select(
        :id, :name, :ecosystem, :description, :homepage, :licenses,
        :repository_url, :versions_count, :first_release_published_at,
        :latest_release_published_at, :metadata,
        :dependent_packages_count, :downloads, :rankings
      )
      .each_row do |row|
        metadata = JSON.parse(row['metadata']) rescue {}
        rankings = JSON.parse(row['rankings']) rescue {}

        puts CSV.generate_line([
          row['id'], row['name'], row['ecosystem'], row['description'], row['homepage'], row['licenses'],
          row['repository_url'], row['versions_count'], row['first_release_published_at'],
          row['latest_release_published_at'], metadata.to_json,
          row['dependent_packages_count'], row['downloads'], rankings.to_json
        ])
      end
  end

  desc 'Export top packages advisories to CSV (usage: rake exports:advisories PERCENT=1 ECOSYSTEM=npm)'
  task advisories: :environment do
    percent = ENV['PERCENT']&.to_f || 1.0
    ecosystem = ENV['ECOSYSTEM']

    puts CSV.generate_line(['package_id', 'advisories'])

    scope = Package.active.top(percent).with_advisories
    if ecosystem.present?
      registry = Registry.where(ecosystem: ecosystem, default: true).first
      scope = scope.where(registry_id: registry.id) if registry
    end

    scope
      .select(:id, :advisories)
      .each_row do |row|
        advisories = JSON.parse(row['advisories']) rescue []
        puts CSV.generate_line([row['id'], advisories.to_json])
      end
  end

  desc 'Export top packages issue metadata to CSV (usage: rake exports:issue_metadata PERCENT=1 ECOSYSTEM=npm)'
  task issue_metadata: :environment do
    percent = ENV['PERCENT']&.to_f || 1.0
    ecosystem = ENV['ECOSYSTEM']

    puts CSV.generate_line([
      'package_id', 'issues_count', 'pull_requests_count', 'avg_time_to_close_issue',
      'avg_time_to_close_pull_request', 'issues_closed_count', 'pull_requests_closed_count',
      'pull_request_authors_count', 'issue_authors_count', 'avg_comments_per_issue',
      'avg_comments_per_pull_request', 'merged_pull_requests_count', 'past_year_issues_count',
      'past_year_pull_requests_count', 'past_year_avg_time_to_close_issue',
      'past_year_avg_time_to_close_pull_request', 'past_year_issues_closed_count',
      'past_year_pull_requests_closed_count', 'past_year_pull_request_authors_count',
      'past_year_issue_authors_count', 'past_year_avg_comments_per_issue',
      'past_year_avg_comments_per_pull_request', 'past_year_bot_issues_count',
      'past_year_bot_pull_requests_count', 'past_year_merged_pull_requests_count'
    ])

    scope = Package.active.top(percent).with_issue_metadata
    if ecosystem.present?
      registry = Registry.where(ecosystem: ecosystem, default: true).first
      scope = scope.where(registry_id: registry.id) if registry
    end

    scope
      .select(:id, :issue_metadata)
      .each_row do |row|
        metadata = JSON.parse(row['issue_metadata']) rescue {}
        puts CSV.generate_line([
          row['id'],
          metadata['issues_count'],
          metadata['pull_requests_count'],
          metadata['avg_time_to_close_issue'],
          metadata['avg_time_to_close_pull_request'],
          metadata['issues_closed_count'],
          metadata['pull_requests_closed_count'],
          metadata['pull_request_authors_count'],
          metadata['issue_authors_count'],
          metadata['avg_comments_per_issue'],
          metadata['avg_comments_per_pull_request'],
          metadata['merged_pull_requests_count'],
          metadata['past_year_issues_count'],
          metadata['past_year_pull_requests_count'],
          metadata['past_year_avg_time_to_close_issue'],
          metadata['past_year_avg_time_to_close_pull_request'],
          metadata['past_year_issues_closed_count'],
          metadata['past_year_pull_requests_closed_count'],
          metadata['past_year_pull_request_authors_count'],
          metadata['past_year_issue_authors_count'],
          metadata['past_year_avg_comments_per_issue'],
          metadata['past_year_avg_comments_per_pull_request'],
          metadata['past_year_bot_issues_count'],
          metadata['past_year_bot_pull_requests_count'],
          metadata['past_year_merged_pull_requests_count']
        ])
      end
  end

  desc 'Export top packages repo metadata to CSV (usage: rake exports:repo_metadata PERCENT=1 ECOSYSTEM=npm)'
  task repo_metadata: :environment do
    percent = ENV['PERCENT']&.to_f || 1.0
    ecosystem = ENV['ECOSYSTEM']

    puts CSV.generate_line([
      'package_id', 'id', 'full_name', 'description', 'fork', 'pushed_at',
      'stargazers_count', 'open_issues_count', 'forks_count', 'subscribers_count',
      'topics', 'homepage', 'language', 'has_issues', 'created_at', 'updated_at',
      'commit_stats', 'scorecard_score'
    ])

    scope = Package.active.top(percent).with_repo_metadata
    if ecosystem.present?
      registry = Registry.where(ecosystem: ecosystem, default: true).first
      scope = scope.where(registry_id: registry.id) if registry
    end

    scope
      .select(:id, :repo_metadata)
      .each_row do |row|
        metadata = JSON.parse(row['repo_metadata']) rescue {}
        scorecard = metadata['scorecard'] || {}
        scorecard_score = scorecard['score']

        puts CSV.generate_line([
          row['id'],
          metadata['id'],
          metadata['full_name'],
          metadata['description'],
          metadata['fork'],
          metadata['pushed_at'],
          metadata['stargazers_count'],
          metadata['open_issues_count'],
          metadata['forks_count'],
          metadata['subscribers_count'],
          metadata['topics']&.to_json,
          metadata['homepage'],
          metadata['language'],
          metadata['has_issues'],
          metadata['created_at'],
          metadata['updated_at'],
          metadata['commit_stats']&.to_json,
          scorecard_score
        ])
      end
  end
end