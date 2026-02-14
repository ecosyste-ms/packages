def with_rake_lock(task_name, ttl: 3600)
  lock_key = "rake:lock:#{task_name}"
  acquired = REDIS.set(lock_key, Process.pid, nx: true, ex: ttl)
  unless acquired
    puts "Skipping #{task_name}: already running (lock held by pid #{REDIS.get(lock_key)})"
    return
  end
  begin
    yield
  ensure
    REDIS.del(lock_key)
  end
end

namespace :packages do
  desc 'sync recently updated packages'
  task sync_recent: :environment do
    with_rake_lock('packages:sync_recent') do
      Registry.sync_all_recently_updated_packages_async
    end
  end

  desc 'sync recently updated npm packages'
  task sync_recent_npm: :environment do
    with_rake_lock('packages:sync_recent_npm') do
      r = Registry.find_by(ecosystem: 'npm')
      r.sync_recently_updated_packages_async
    end
  end

  desc 'sync_worst_one_percent'
  task sync_worst_one_percent: :environment do
    with_rake_lock('packages:sync_worst_one_percent') do
      Registry.sync_worst_one_percent
    end
  end

  desc 'sync all packages'
  task sync_all: :environment do
    Registry.sync_all_packages
  end

  desc 'sync all packages async'
  task sync_all_async: :environment do
    Registry.sync_all_packages_async
  end

  desc 'sync least recently synced packages'
  task sync_least_recent: :environment do
    with_rake_lock('packages:sync_least_recent') do
      Package.sync_least_recent_async
    end
  end

  desc 'sync least recently synced top 1% packages'
  task sync_least_recent_top: :environment do
    with_rake_lock('packages:sync_least_recent_top') do
      Package.sync_least_recent_top_async
    end
  end

  desc 'check package statuses'
  task check_statuses: :environment do
    with_rake_lock('packages:check_statuses') do
      Package.check_statuses_async
    end
  end

  desc "sync missing packages"
  task sync_missing: :environment do
    with_rake_lock('packages:sync_missing') do
      Registry.sync_all_missing_packages_async
    end
  end

  desc 'update repo metadata'
  task update_repo_metadata: :environment do
    with_rake_lock('packages:update_repo_metadata') do
      Package.update_repo_metadata_async
    end
  end

  desc "parse unique maven names"
  task parse_maven_names: :environment do
    names = Set.new

    File.readlines('terms.txt').each_with_index do |line,i|
      parts = line.split('|')
      names.add [[parts[0], parts[1]].join(':')]
      puts "#{i} row (#{names.length} uniq names)" if i % 10000 == 0
    end
  
    puts names.length
    File.write('unique-terms.txt', names.to_a.join("\n"))
  end

  desc 'sync package download counts'
  task sync_download_counts: :environment do
    with_rake_lock('packages:sync_download_counts') do
      Package.sync_download_counts_async
    end
  end

  desc 'update_extra_counts'
  task update_extra_counts: :environment do
    with_rake_lock('packages:update_extra_counts') do
      Registry.update_extra_counts
    end
  end

  desc 'sync maintainers'
  task sync_maintainers: :environment do
    with_rake_lock('packages:sync_maintainers') do
      Package.sync_maintainers_async
    end
  end

  desc 'update rankings'
  task update_rankings: :environment do
    with_rake_lock('packages:update_rankings') do
      Package.update_rankings_async
    end
  end

  desc 'update advisories'
  task update_advisories: :environment do
    with_rake_lock('packages:update_advisories') do
      Package.update_advisories
    end
  end

  desc 'update docker usages'
  task update_docker_usages: :environment do
    with_rake_lock('packages:update_docker_usages') do
      Package.update_docker_usages
    end
  end

  desc 'crawl github marketplace'
  task crawl_github_marketplace: :environment do
    registry = Registry.find_by(ecosystem: 'actions')
    repo_names = registry.ecosystem_instance.crawl_marketplace
    registry = Registry.find_by(ecosystem: 'actions')
    repo_names.each do |repo_name|
      registry.sync_package_async(repo_name)
    end
  end

  desc 'crawl recently updated github marketplace'
  task crawl_recently_updated_github_marketplace: :environment do
    with_rake_lock('packages:crawl_recently_updated_github_marketplace') do
      registry = Registry.find_by(ecosystem: 'actions')
      repo_names = registry.ecosystem_instance.crawl_recent_marketplace
      repo_names.each do |repo_name|
        registry.sync_package_async(repo_name)
      end
    end
  end

  desc 'sync docker packages'
  task sync_outdated_docker: :environment do
    with_rake_lock('packages:sync_outdated_docker') do
      registry = Registry.find_by(ecosystem: 'docker')
      registry.packages.active.outdated.limit(1000).order('RANDOM()').each do |package|
        puts package.name
        package.sync_async
        sleep 1 # rate limited
      end
    end
  end

  desc 'sync batch registries outdated'
  task sync_batch_registries_outdated: :environment do
    with_rake_lock('packages:sync_batch_registries_outdated') do
      Registry.sync_in_batches_outdated
    end
  end

  desc 'calculate funding domains'
  task calculate_funding_domains: :environment do
    with_rake_lock('packages:calculate_funding_domains') do
      Package.funding_domains
    end
  end

  desc 'update critical packages'
  task update_critical: :environment do
    Registry.all.find_each do |registry|
      registry.find_critical_packages
    end
  end

  desc 'clean up sidekiq unique jobs'
  task clean_up_sidekiq_unique_jobs: :environment do
    with_rake_lock('packages:clean_up_sidekiq_unique_jobs') do
      SidekiqUniqueJobs::Digests.new.delete_by_pattern("*", count: 10_000)
      SidekiqUniqueJobs::ExpiringDigests.new.delete_by_pattern("*", count: 10_000)
    end
  end

  desc 'report upstream ecosystem groupings for nixpkgs packages'
  task nixpkgs_upstream_ecosystems: :environment do
    registry = Registry.where(ecosystem: 'nixpkgs').order(packages_count: :desc).first
    abort "No nixpkgs registry found" unless registry

    puts "Registry: #{registry.name} (#{registry.packages_count} packages)"
    puts

    prefix_mappings = {
      /^python\d*Packages\./ => 'pypi',
      /^rubyPackages\./ => 'rubygems',
      /^nodePackages(?:_latest)?\./ => 'npm',
      /^perl\d*Packages\./ => 'cpan',
      /^haskellPackages\./ => 'hackage',
      /^ocamlPackages\./ => 'opam',
      /^lua\d*Packages\./ => 'luarocks',
      /^luajitPackages\./ => 'luarocks',
      /^rPackages\./ => 'cran',
      /^beamPackages\./ => 'hex',
      /^emacsPackages\./ => 'elpa',
      /^coqPackages\./ => 'opam',
      /^idrisPackages\./ => 'hackage',
      /^octavePackages\./ => 'octave',
      /^chickenPackages_\d+\./ => 'chicken',
      /^akkuPackages\./ => 'akku',
    }

    counts = Hash.new(0)
    registry.packages.active.select(:id, :name).each_instance do |pkg|
      ecosystem = prefix_mappings.detect { |pattern, _| pkg.name =~ pattern }&.last
      counts[ecosystem.presence || '(none)'] += 1
      print "."
    end
    puts

    counts.sort_by { |_, v| -v }.each do |label, count|
      puts "  #{label}: #{count}"
    end

    total_with = counts.reject { |k, _| k == '(none)' }.values.sum
    puts
    puts "Total with upstream mapping: #{total_with}"
    puts "Total without: #{counts['(none)']}"
  end

  desc 'report native/system dependencies of nixpkgs python packages'
  task nixpkgs_python_native_deps: :environment do
    registry = Registry.where(ecosystem: 'nixpkgs').order(packages_count: :desc).first
    abort "No nixpkgs registry found" unless registry

    # Build set of known python package bare names
    # e.g. "python311Packages.numpy" -> "numpy"
    python_names = Set.new
    python_package_ids = []
    registry.packages.active.select(:id, :name).each_instance do |pkg|
      next unless pkg.name =~ /^python\d*Packages\./
      bare = pkg.name.sub(/^python\d*Packages\./, '')
      python_names << bare
      next if bare == 'jsonnet'
      python_package_ids << pkg.id
    end
    puts "Known python package names: #{python_names.size}"

    # Nix builtins and python build tooling to ignore
    ignore = Set.new(%w[
      lib stdenv stdenvNoCC fetchurl fetchFromGitHub fetchFromGitLab fetchgit
      fetchzip fetchpatch fetchpatch2 makeWrapper writeText writeScript runCommand
      symlinkJoin buildEnv callPackage mkDerivation overrideAttrs
      optional optionals mkIf then else if inherit src version pname
      meta maintainers platforms homepage description license
      pytestCheckHook pythonImportsCheckHook pythonRelaxDepsHook
      setuptools wheel pip flit-core poetry-core hatchling hatch-vcs
      cython cython_0 meson-python meson ninja cmake pkg-config
      buildPythonPackage fetchPypi python pythonOlder pythonAtLeast
      substituteAll versionCheckHook writePythonModule
      unittestCheckHook sphinxHook autopatchelfHook autoPatchelfHook
      autoreconfHook addOpenGLRunpath installShellFiles unzip
      pkgs python3 python3Packages pythonPackages rustPlatform
      cargo rustc which typing enum34
      toPythonApplication ensureNewerSourcesForZipFilesHook
      removeReferencesTo memorymappingHook memstreamHook
      wrapGAppsHook wrapQtAppsHook npmHooks autoAddOpenGLRunpathHook
      buildPackages pythonForBuild nukeReferences configd
      cc out
    ])

    # For each python package, find deps that aren't python or ignored
    results = Hash.new { |h, k| h[k] = { count: 0, examples: [] } }

    python_package_ids.each_slice(500) do |batch_ids|
      Version.where(package_id: batch_ids)
             .includes(:dependencies, :package)
             .each_instance do |version|
        version.dependencies.each do |dep|
          name = dep.package_name
          next if python_names.include?(name)
          next if ignore.include?(name)

          results[name][:count] += 1
          pkg_bare = version.package.name.sub(/^python\d*Packages\./, '')
          results[name][:examples] << pkg_bare if results[name][:examples].size < 3
        end
        print "."
      end
    end
    puts
    $stderr.puts "Native/system dependencies found: #{results.size}"

    puts "dependency,python_package_count,examples"
    results.sort_by { |_, v| -v[:count] }.each do |name, data|
      puts "#{name},#{data[:count]},#{data[:examples].join(';')}"
    end;nil
  end

  desc 'list nixpkgs python packages and their native/system dependencies'
  task nixpkgs_python_packages_with_native_deps: :environment do
    registry = Registry.where(ecosystem: 'nixpkgs').order(packages_count: :desc).first
    abort "No nixpkgs registry found" unless registry

    python_names = Set.new
    python_package_ids = []
    registry.packages.active.select(:id, :name).each_instance do |pkg|
      next unless pkg.name =~ /^python\d*Packages\./
      bare = pkg.name.sub(/^python\d*Packages\./, '')
      python_names << bare
      next if bare == 'jsonnet'
      python_package_ids << pkg.id
    end
    $stderr.puts "Python packages: #{python_package_ids.size}"

    ignore = Set.new(%w[
      lib stdenv stdenvNoCC fetchurl fetchFromGitHub fetchFromGitLab fetchgit
      fetchzip fetchpatch fetchpatch2 makeWrapper writeText writeScript runCommand
      symlinkJoin buildEnv callPackage mkDerivation overrideAttrs
      optional optionals mkIf then else if inherit src version pname for the
      meta maintainers platforms homepage description license
      pytestCheckHook pythonImportsCheckHook pythonRelaxDepsHook
      setuptools wheel pip flit-core poetry-core hatchling hatch-vcs
      cython cython_0 meson-python meson ninja cmake pkg-config
      buildPythonPackage fetchPypi python pythonOlder pythonAtLeast
      substituteAll versionCheckHook writePythonModule
      unittestCheckHook sphinxHook autopatchelfHook autoPatchelfHook
      autoreconfHook addOpenGLRunpath installShellFiles unzip
      pkgs python3 python3Packages pythonPackages rustPlatform
      cargo rustc which typing enum34
      Security CoreServices CoreFoundation ApplicationServices
      Cocoa Foundation AppKit Accelerate IOKit CoreAudio AudioToolbox
      AudioUnit CoreGraphics CoreVideo CoreMIDI CFNetwork Carbon
      VideoDecodeAcceleration OpenGL GSS PCSC
      toPythonApplication ensureNewerSourcesForZipFilesHook
      removeReferencesTo memorymappingHook memstreamHook
      wrapGAppsHook wrapQtAppsHook npmHooks autoAddOpenGLRunpathHook
      buildPackages pythonForBuild nukeReferences configd
      cc out needed with to docs tests
      findXMLCatalogs darwin
      isPy3k functools32 futures backports backports_os
      AX_CHECK_COMPILE_FLAG moveBuildTree
      pkgs-systemd pkgs-docker
    ])

    results = Hash.new { |h, k| h[k] = [] }

    python_package_ids.each_slice(500) do |batch_ids|
      Version.where(package_id: batch_ids)
             .includes(:dependencies, :package)
             .each_instance do |version|
        pkg_bare = version.package.name.sub(/^python\d*Packages\./, '')
        version.dependencies.each do |dep|
          name = dep.package_name
          next if python_names.include?(name)
          next if ignore.include?(name)
          results[pkg_bare] << "#{name} (#{dep.kind})"
        end
        print "."
      end
    end
    puts
    $stderr.puts "Python packages with native deps: #{results.size}"

    puts "python_package,native_dependency_count,native_dependencies"
    results.sort_by { |_, v| -v.size }.each do |pkg, deps|
      puts "#{pkg},#{deps.size},#{deps.uniq.join(';')}"
    end;nil
  end
end