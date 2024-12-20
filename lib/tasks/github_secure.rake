namespace :github_secure do
  desc "most popular packages, hosted on github, created within the past year"
  task :new_projects do
    start_date = Date.new(2023, 12, 31).end_of_year
    excluded_ecosystems = ['bower','docker']

    candidates = Package.active.with_repo_metadata.where.not(ecosystem: excluded_ecosystems).where('first_release_published_at > ?', start_date).top(20)

    this_year = candidates.select do |package|
      Date.parse(package.repo_metadata['created_at']) > start_date
    end

    table = []

    this_year.group_by(&:repository_url).each do |url, packages|
      next unless url && url.include?('github.com')
      ecosystem = packages.map(&:ecosystem).group_by(&:itself).sort_by(&:last).reverse.first.first
      total_downloads = packages.sum{ |p| p.downloads || 0 }
      total_dependent_packages = packages.sum{ |p| p.dependent_packages_count || 0 }
      total_dependent_repos_count = packages.sum{ |p| p.dependent_repos_count || 0 }
      sum = total_downloads + total_dependent_packages + total_dependent_repos_count
      table << [url, ecosystem, total_downloads, total_dependent_packages, total_dependent_repos_count, sum]
    end

    ecosystems = table.map(&:second).uniq

    csv = CSV.generate do |csv|
      csv << ['url', 'ecosystem', 'downloads', 'dependent_packages', 'dependent_repos', 'sum']
      ecosystems.each do |ecosystem|
        table.select{ |row| row[1] == ecosystem }.sort_by(&:last).reverse.first(30).each do |row|
          next if row[5] < 100
          csv << row
        end  
      end
    end

    puts csv.to_s
  end

  desc "most used dev/test/build dependencies, hosted on github"
  task :dev_dependencies do
    dev_kinds = ['Development', 'compile', 'test','dev', 'development', 'tests', 'testing', 'build', 'develop', 'doc', 'docs', 'lint', 'benchmarking']
    
    dev_dependencies = {}
    i = 0

    Dependency.where(kind: dev_kinds).each_instance do |dependency|
      i += 1
      print "#{i}\r"
      dev_dependencies[dependency['ecosystem']] ||= {}
      dev_dependencies[dependency['ecosystem']][dependency['package_name']] ||= 0
      dev_dependencies[dependency['ecosystem']][dependency['package_name']] += 1
    end

    pkgs = []
    
    dev_dependencies.each do |ecosystem, packages|
      next if ecosystem == 'bower'
      packages.sort_by(&:last).reverse.first(50).each do |package, count|
        puts "#{ecosystem} #{package} #{count}"
        package_record = Package.find_by(ecosystem: ecosystem, name: package)
        next unless package_record
        pkgs << [ecosystem, package, package_record.repository_url, count]
      end
    end;nil

    csv = CSV.generate do |csv|
      csv << ['ecosystem', 'package', 'url', 'dev deps count']
      pkgs.each do |row|
        next unless row[2].present? && row[2].include?('github.com')
        csv << row
      end
    end

    puts csv.to_s
  end

  desc "critical packages, active in the past year, with lowest engagement"
  task :unseen_critical do
    start_date = Date.new(2023, 12, 31).end_of_year
    excluded_ecosystems = ['bower','docker']

    candidates = Package.critical.active.with_repo_metadata.where.not(ecosystem: excluded_ecosystems).where('latest_release_published_at > ?', start_date)

    table = []

    candidates.group_by(&:repository_url).each do |url, packages|
      next unless url && url.include?('github.com')
      ecosystem = packages.map(&:ecosystem).group_by(&:itself).sort_by(&:last).reverse.first.first
      total_downloads = packages.sum{ |p| p.downloads || 0 }
      total_dependent_packages = packages.sum{ |p| p.dependent_packages_count || 0 }
      total_dependent_repos_count = packages.sum{ |p| p.dependent_repos_count || 0 }
      sum = total_downloads + total_dependent_packages + total_dependent_repos_count
      stars = packages.map{ |p| p.repo_metadata['stargazers_count'] || 0 }.first
      forks = packages.map{ |p| p.repo_metadata['forks_count'] || 0 }.first
      watchers = packages.map{ |p| p.repo_metadata['watchers_count'] || 0 }.first
      attention_sum = stars + forks + watchers
      ratio = attention_sum.to_f / sum.to_f
      table << [url, ecosystem, total_downloads, total_dependent_packages, total_dependent_repos_count, stars, forks, watchers, sum, attention_sum, ratio]
    end

    ecosystems = table.map(&:second).uniq

    csv = CSV.generate do |csv|
      csv << ['url', 'ecosystem', 'downloads', 'dependent_packages', 'dependent_repos', 'stars', 'forks', 'watchers', 'usage_sum', 'attention_sum', 'ratio']
      ecosystems.each do |ecosystem|
        table.select{ |row| row[1] == ecosystem }.sort_by{|r| r[9]}.first(20).each do |row|
          next unless row[0].include?('github.com') 
          csv << row
        end  
      end
    end

    puts csv.to_s
  end
end

